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
	/// The types whose lack of a production `@Instantiable` declaration is an error in a module that holds or calls a
	/// seam: those the roots' trees reach outside every seam's tree, the fills this module generates for the holes of the
	/// foreign seams they call included, and those a seam's tree reaches through a dependency that cannot be a hole
	/// (`canBeHole`), since only hand-written code could build its type.
	/// - Parameter foreignSeamRoots: The signatures of the foreign seams this module's trees reach
	///   (`computeForeignSeamRoots()`).
	func typesReachableOutsideSeamTrees(foreignSeamRoots: [TypeDescription: ScopeGenerator.SeamRoot?]) throws -> Set<TypeDescription> {
		/// The seam `typeDescription` is, when its tree is another tree's leaf: one with a signature, generated here or
		/// in another module.
		func isSeamWithTree(_ instantiable: Instantiable) -> Bool {
			guard instantiable.generatesDependencyTree else { return false }
			return generatedSeamTypes.contains(instantiable.concreteInstantiable)
				|| (foreignSeamRoots[instantiable.concreteInstantiable] ?? nil) != nil
		}
		/// The types a walk from `roots` reaches without entering a seam with a tree other than the roots, entering the
		/// fills this module generates for the holes of each foreign seam it reaches.
		func typesReached(from roots: Set<TypeDescription>) -> Set<TypeDescription> {
			var reached = Set<TypeDescription>()
			var typesToVisit = Array(roots)
			while let typeDescription = typesToVisit.popLast() {
				guard reached.insert(typeDescription).inserted,
				      let instantiable = typeDescriptionToFulfillingInstantiableMap[typeDescription]
				else { continue }
				if !roots.contains(typeDescription), isSeamWithTree(instantiable) {
					for hole in (foreignSeamRoots[instantiable.concreteInstantiable] ?? nil)?.signature.holes ?? [] {
						if let fulfillingInstantiable = Self.fulfillingInstantiable(of: hole, in: typeDescriptionToFulfillingInstantiableMap) {
							typesToVisit.append(fulfillingInstantiable.concreteInstantiable)
						}
					}
					continue
				}
				for dependency in instantiable.dependencies where dependency.isInstantiated && instantiates(dependency) {
					typesToVisit.append(dependency.asInstantiatedType)
				}
			}
			return reached
		}
		var typesToReport = typesReached(from: rootInstantiables)
		// A seam whose module SafeDI does not know cannot take a builder: what its callers see is unknown.
		if let emittingModule, emittingModule.identity.moduleName == nil {
			var holes = [DependencyTreeGeneratorError.HoleInSeamOfUnnamedModule]()
			var reportedLocations = Set<String>()
			for seamType in generatedSeamTypes.sorted() {
				guard let seam = typeDescriptionToFulfillingInstantiableMap[seamType] else { continue }
				for typeDescription in typesReached(from: [seamType]).sorted() {
					guard let instantiable = typeDescriptionToFulfillingInstantiableMap[typeDescription] else { continue }
					for dependency in instantiable.dependencies where dependency.isInstantiated
						&& !dependency.isInstantiatedOnlyIfAvailable
						&& Self.canBeHole(dependency)
						&& typeDescriptionToFulfillingInstantiableMap[dependency.asInstantiatedType]?.mockOnly != false
						&& reportedLocations.insert(dependency.declarationLocation.map(\.identity) ?? "\(typeDescription.asSource).\(dependency.property.label)").inserted
					{
						holes.append(.init(seam: seam.concreteInstantiable, owner: instantiable.concreteInstantiable, dependency: dependency))
					}
				}
			}
			if !holes.isEmpty {
				throw DependencyTreeGeneratorError.holesInSeamsOfUnnamedModule(holes)
			}
		}
		// Only hand-written code could build a type that cannot be a hole. Found once: looked up for each type a seam reaches,
		// it scanned every declaration once per seam.
		var typesInstantiatedAsNoHole = Set<TypeDescription>()
		for instantiable in typeDescriptionToFulfillingInstantiableMap.values {
			for dependency in instantiable.dependencies where dependency.isInstantiated && !Self.canBeHole(dependency) {
				typesInstantiatedAsNoHole.insert(dependency.asInstantiatedType)
			}
		}
		for seamType in generatedSeamTypes {
			for typeDescription in typesReached(from: [seamType]) where typeDescriptionToFulfillingInstantiableMap[typeDescription]?.mockOnly != false {
				if typesInstantiatedAsNoHole.contains(typeDescription) {
					typesToReport.insert(typeDescription)
				}
			}
		}
		return typesToReport
	}

	/// The types the trees rooted at `roots` reach, beneath the seams other modules declare included.
	func typesReachable(fromRoots roots: Set<TypeDescription>) -> Set<TypeDescription> {
		var reachableTypeDescriptions = Set<TypeDescription>()
		// The types reached whose instantiated types are not yet recorded. A worklist rather than recursion,
		// since a chain of types can be as long as the module has types.
		var typeDescriptionsToVisit = Array(roots)
		while let reachableTypeDescription = typeDescriptionsToVisit.popLast() {
			guard reachableTypeDescriptions.insert(reachableTypeDescription).inserted else {
				// We've visited this tree already. Ignore.
				continue
			}
			guard let instantiable = typeDescriptionToFulfillingInstantiableMap[reachableTypeDescription] else {
				// We can't find an instantiable for this type.
				// This is bad, but we'll handle this error in `validateReachableTypeDescriptions()`.
				continue
			}
			for dependency in instantiable.dependencies where dependency.isInstantiated && instantiates(dependency) {
				typeDescriptionsToVisit.append(dependency.asInstantiatedType)
			}
		}
		return reachableTypeDescriptions
	}

	/// Whether a production tree instantiates `dependency`, an `@Instantiated` one: always, unless it is declared with
	/// `onlyIfAvailable: true` and no production declaration this module reads fulfills its type – none at all, or only a
	/// `mockOnly` one, which only mocks build. Such a dependency reaches no type, so its type is never reported as one no
	/// declaration fulfills, no scope builds it, and generated code passes `nil` for it.
	func instantiates(_ dependency: Dependency) -> Bool {
		!dependency.isInstantiatedOnlyIfAvailable
			|| typeDescriptionToFulfillingInstantiableMap[dependency.asInstantiatedType]?.mockOnly == false
	}

	/// What a scope generates for `dependency`, an `@Instantiated(onlyIfAvailable: true)` one no production declaration
	/// fulfills (`instantiates(_:)`): a scope of its own that builds nothing and binds the property to `nil`
	/// (`Scope.isUnavailableDependency`), never erased, since there is no value to erase. The trees of a module that generates
	/// no seam bind it so. In a module that generates or calls one, the property is a hole (`populatePropertiesToGenerate`):
	/// a seam's tree takes a builder that returns the optional, and a root's tree, which takes none, binds `nil`
	/// (`SeamHoles.takesBuilders`). Every mock binds it so too, a public mock's and a seam's own included, which take no
	/// builder for it, a deliberate gap from the seam's initializer ("Instantiated only if available" in
	/// `.claude/rules/test-design.md`).
	static func unavailableDependency(_ dependency: Dependency) -> Scope.PropertyToGenerate {
		.instantiated(
			dependency.property,
			Scope(
				instantiable: Instantiable(
					instantiableType: dependency.asInstantiatedType,
					isRoot: false,
					initializer: nil,
					additionalInstantiables: nil,
					dependencies: [],
					declarationType: .structType,
					access: AccessDeclaration(level: .public),
				),
				isUnavailableDependency: true,
			),
			erasedToConcreteExistential: false,
		)
	}

	/// The alias of `dependency`, an aliased dependency `instantiable` declares, as a scope of `instantiable` generates it,
	/// in every scope map.
	static func aliasedDependency(
		_ dependency: Dependency,
		fulfilledBy fulfillingProperty: Property,
		erasedToConcreteExistential: Bool,
		onlyIfAvailable: Bool,
		declaredBy instantiable: Instantiable,
	) -> Scope.PropertyToGenerate {
		.aliased(
			dependency.property,
			fulfilledBy: fulfillingProperty,
			erasedToConcreteExistential: erasedToConcreteExistential,
			onlyIfAvailable: onlyIfAvailable,
			// The assignment names its declaration by the declaring type, spelled as generated code spells it, and the
			// alias’s label: no file or line, which would differ between integrations and move with every edit above it.
			declarationReference: "\(instantiable.concreteInstantiable.asSource).\(dependency.property.label)",
		)
	}

	func createTypeDescriptionToScopeMapping() throws -> [TypeDescription: Scope] {
		// Create the mapping.
		let typeDescriptionToScopeMap: [TypeDescription: Scope] = reachableTypeDescriptions
			.reduce(into: [TypeDescription: Scope]()) { partialResult, typeDescription in
				if let instantiable = typeDescriptionToFulfillingInstantiableMap[typeDescription],
				   partialResult[instantiable.concreteInstantiable] == nil
				{
					let scope = Scope(instantiable: instantiable, builtInlineSeamComment: builtInlineSeamComment(for: instantiable))
					for instantiableType in instantiable.instantiableTypes {
						partialResult[instantiableType] = scope
					}
				}
			}

		// Populate the propertiesToGenerate on each scope. Scopes hash by identity, so they are
		// visited in an order that changes from run to run, and every dependency that cannot be
		// instantiated is reported, in source order.
		var forwardedPropertyErrors = [DependencyTreeGeneratorError]()
		for scope in Set(typeDescriptionToScopeMap.values) {
			for dependency in scope.instantiable.dependencies {
				switch dependency.source {
				case let .instantiated(_, erasedToConcreteExistential):
					let instantiatedType = dependency.asInstantiatedType
					if let instantiable = typeDescriptionToFulfillingInstantiableMap[instantiatedType],
					   let instantiatedScope = typeDescriptionToScopeMap[instantiatedType]
					{
						if let error = forwardedPropertyError(
							for: dependency,
							instantiable: instantiable,
							parent: scope.instantiable,
						) {
							forwardedPropertyErrors.append(error)
						}
						scope.propertiesToGenerate.append(.instantiated(
							dependency.property,
							instantiatedScope,
							erasedToConcreteExistential: erasedToConcreteExistential,
						))
					} else if !instantiates(dependency) {
						scope.propertiesToGenerate.append(Self.unavailableDependency(dependency))
					}
				case let .aliased(fulfillingProperty, erasedToConcreteExistential, onlyIfAvailable):
					scope.propertiesToGenerate.append(Self.aliasedDependency(
						dependency,
						fulfilledBy: fulfillingProperty,
						erasedToConcreteExistential: erasedToConcreteExistential,
						onlyIfAvailable: onlyIfAvailable,
						declaredBy: scope.instantiable,
					))
				case .forwarded, .received:
					continue
				}
			}
		}
		if let error = DependencyTreeGeneratorError.reportingAll(of: forwardedPropertyErrors) {
			throw error
		}
		return typeDescriptionToScopeMap
	}

	/// What creating an instance of an `@Instantiable` type reads by value, for `generateWarnings(validatedScopes:)`.
	///
	/// Creating a type creates its constant dependencies along with it, and theirs. A dependency behind an
	/// `Instantiator` is created later, when asked for. A lazily instantiated dependency is created along with
	/// the type only if something that is created along with it reads the dependency’s instance.
	struct InstantiationAnalysis {
		/// A type that reads a dependency by value while it is created.
		struct Reader {
			let instantiable: Instantiable
			/// The property with which that type declares the dependency.
			let property: Property
			/// The label of the dependency that type receives: `property`'s own, or for an alias the label it renames.
			let receivedLabel: String
			/// Where that type declares `property`.
			let declarationLocation: Dependency.DeclarationLocation?
		}

		/// A lazily instantiated dependency that is instantiated whenever the type declaring it is created.
		struct LazilyInstantiatedPropertyInstantiatedWithOwner {
			let property: Property
			let declarationLocation: Dependency.DeclarationLocation?
			/// The property that receives the dependency’s instance by value.
			let instanceProperty: Property
			/// The first type, in declaration order, whose creation reads the instance.
			let reader: Reader

			func warning(owner: Instantiable) -> SourceDiagnostic {
				let ownerName = owner.concreteInstantiable.asSource
				let cause = if reader.instantiable.concreteInstantiable == owner.concreteInstantiable {
					"`\(ownerName)` renames the instance to `\(reader.property.asSource)`. Declare `\(instanceProperty.asSource)` instead, or read `\(property.label).\(Dependency.lazilyInstantiatedInstancePropertyName)` where `\(ownerName)` needs it."
				} else {
					"`\(reader.instantiable.concreteInstantiable.asSource)` is created with `\(ownerName)` and receives the instance as `\(reader.property.asSource)`. To instantiate it lazily, receive `\(reader.receivedLabel): \(property.typeDescription.unwrapped.asSource)` on `\(reader.instantiable.concreteInstantiable.asSource)`."
				}
				return SourceDiagnostic(
					severity: .warning,
					location: declarationLocation,
					message: "@\(Dependency.Source.instantiatedRawValue) property `\(property.asSource)` is instantiated whenever `\(ownerName)` is created: \(cause)",
				)
			}
		}

		/// The dependencies the type’s creation reads by value from further up the tree, keyed by the property
		/// that receives each, with the type that reads it.
		var readFromAncestors = [Property: Reader]()
		/// The type’s own lazily instantiated dependencies that its creation instantiates, in declaration order.
		var lazilyInstantiatedPropertiesInstantiatedWithOwner = [LazilyInstantiatedPropertyInstantiatedWithOwner]()
	}

	/// - Returns: What creating an instance of `scope`’s type reads by value. See `InstantiationAnalysis`.
	static func instantiationAnalysis(
		of scope: Scope,
		cache: inout [ObjectIdentifier: InstantiationAnalysis],
	) -> InstantiationAnalysis {
		let scopeIdentifier = ObjectIdentifier(scope)
		if let cachedAnalysis = cache[scopeIdentifier] {
			return cachedAnalysis
		} else {
			// Analyze the scopes created along with this one first, each after those created along with it, so that
			// the analysis below reads theirs from the cache. A chain of them can be as long as the module has types.
			for createdScope in unanalyzedScopes(createdAlongWith: scope, cache: cache) {
				_ = instantiationAnalysis(of: createdScope, cache: &cache)
			}
			let instantiable = scope.instantiable
			var declarationLocations = [Property: Dependency.DeclarationLocation]()
			// A receive binds to the nearest declaration of its label, so nothing this type declares is read from further up.
			var declaredLabels = Set<String>()
			// Every by-value read made while this type is created, whether of its own dependencies or of an ancestor’s.
			var readWhileCreated = [Property: InstantiationAnalysis.Reader]()
			// Reading the instance of a lazily instantiated property this type renames reads the instance of the
			// property it renames. Keyed by the by-value property of the alias.
			var renamedInstanceProperties = [Property: Property]()
			for dependency in instantiable.dependencies {
				declarationLocations[dependency.property] = dependency.declarationLocation
				switch dependency.source {
				case .instantiated, .forwarded:
					declaredLabels.insert(dependency.property.label)
				case .received:
					break
				case let .aliased(fulfillingProperty, _, _):
					declaredLabels.insert(dependency.property.label)
					if let instanceProperty = dependency.lazilyInstantiatedInstanceProperty,
					   let fulfillingInstanceProperty = fulfillingProperty.asLazilyInstantiatedInstanceProperty
					{
						renamedInstanceProperties[instanceProperty] = fulfillingInstanceProperty
					}
				}
			}
			/// The property whose instance a read of `property` reads: the property a renaming of this type renames, or
			/// `property` itself. No renaming of a type renames another (SafeDITool rejects that before it validates a
			/// tree that builds the scope).
			func propertyRead(by property: Property) -> Property {
				renamedInstanceProperties[property] ?? property
			}
			func recordReads(whileCreating childScope: Scope) {
				// Reads this type renames to one property are recorded as the read of the reader declared first. Sorted by
				// where each reader is declared, so which reader is reported never depends on dictionary iteration, or on
				// the labels of the aliases the reads are renamed through. Reads at one location have one reader.
				for (property, reader) in instantiationAnalysis(of: childScope, cache: &cache).readFromAncestors.sorted(by: {
					Dependency.DeclarationLocation.precedesInSourceOrder($0.value.declarationLocation, $1.value.declarationLocation)
				}) {
					let readProperty = propertyRead(by: property)
					if readWhileCreated[readProperty] == nil {
						readWhileCreated[readProperty] = reader
					}
				}
			}

			/// Records that creating this type reads `property` through `dependency`, unless a dependency declared
			/// earlier reads it, as two renamings of one instance do.
			func recordRead(of property: Property, by dependency: Dependency, receivedLabel: String) {
				if readWhileCreated[property] == nil {
					readWhileCreated[property] = .init(instantiable: instantiable, property: dependency.property, receivedLabel: receivedLabel, declarationLocation: dependency.declarationLocation)
				}
			}
			// The instances of the lazily instantiated properties this type instantiates, which it always creates.
			let instantiatedLazilyInstantiatedInstanceProperties = Set(
				instantiable.dependencies.filter(\.isInstantiated).compactMap(\.lazilyInstantiatedInstanceProperty),
			)
			for dependency in instantiable.dependencies {
				switch dependency.source {
				case .instantiated, .forwarded:
					break
				case let .received(onlyIfAvailable):
					// Whether an `onlyIfAvailable` receive reads the instance depends on the order in which
					// siblings are generated, so it is never taken as the reason a dependency is instantiated.
					if !onlyIfAvailable, dependency.property.propertyType.isConstant {
						recordRead(of: dependency.property, by: dependency, receivedLabel: dependency.property.label)
					}
				case let .aliased(fulfillingProperty, _, onlyIfAvailable):
					// An `onlyIfAvailable` alias is the exception when it renames the instance of a lazily instantiated
					// property this type instantiates: `orderedPropertiesToGenerate` builds an alias after the sibling
					// that fulfills it, and validation rejects a tree that needs the alias first, so it always reads it.
					if fulfillingProperty.propertyType.isConstant,
					   !onlyIfAvailable || instantiatedLazilyInstantiatedInstanceProperties.contains(fulfillingProperty)
					{
						recordRead(of: fulfillingProperty, by: dependency, receivedLabel: fulfillingProperty.label)
					}
				}
			}

			var lazilyInstantiatedChildren = [(property: Property, instanceProperty: Property, scope: Scope)]()
			// A dependency behind an `Instantiator` is created when asked for, not along with this type.
			for case let .instantiated(property, childScope, _) in scope.propertiesToGenerate {
				if let instanceProperty = property.asLazilyInstantiatedInstanceProperty {
					lazilyInstantiatedChildren.append((property, instanceProperty, childScope))
				} else if property.propertyType.isConstant {
					recordReads(whileCreating: childScope)
				}
			}

			// Instantiating one lazily instantiated dependency can read another’s instance, so look again after each.
			var analysis = InstantiationAnalysis()
			while let (child, reader) = lazilyInstantiatedChildren.lazy.compactMap({ child in
				readWhileCreated[child.instanceProperty].map { (child, $0) }
			}).first {
				analysis.lazilyInstantiatedPropertiesInstantiatedWithOwner.append(.init(
					property: child.property,
					declarationLocation: declarationLocations[child.property],
					instanceProperty: child.instanceProperty,
					reader: reader,
				))
				lazilyInstantiatedChildren.removeAll { $0.property == child.property }
				recordReads(whileCreating: child.scope)
			}

			analysis.readFromAncestors = readWhileCreated.filter { !declaredLabels.contains($0.key.label) }
			cache[scopeIdentifier] = analysis
			return analysis
		}
	}

	/// The scopes created along with `scope` – those it instantiates as constants or lazily, and theirs in turn –
	/// whose analysis `cache` lacks, each listed after the scopes created along with it. `scope` is not listed.
	/// The search keeps its own path, since a chain of such scopes can be as long as the module has types.
	private static func unanalyzedScopes(
		createdAlongWith scope: Scope,
		cache: [ObjectIdentifier: InstantiationAnalysis],
	) -> [Scope] {
		/// The scopes `instantiationAnalysis` reads the analysis of when it analyzes `scope`.
		func scopesCreated(alongWith scope: Scope) -> [Scope] {
			var createdScopes = [Scope]()
			for case let .instantiated(property, childScope, _) in scope.propertiesToGenerate
				where property.asLazilyInstantiatedInstanceProperty != nil || property.propertyType.isConstant
			{
				createdScopes.append(childScope)
			}
			return createdScopes
		}
		var unanalyzedScopes = [Scope]()
		var visitedScopes: Set<ObjectIdentifier> = [ObjectIdentifier(scope)]
		// Each scope on the path, with the scopes created along with it and the index of the next one to visit.
		var path = [(scope: scope, createdScopes: scopesCreated(alongWith: scope), nextIndex: 0)]
		while let (pathScope, createdScopes, nextIndex) = path.last {
			if nextIndex < createdScopes.count {
				path[path.count - 1].nextIndex += 1
				let createdScope = createdScopes[nextIndex]
				if cache[ObjectIdentifier(createdScope)] == nil, visitedScopes.insert(ObjectIdentifier(createdScope)).inserted {
					path.append((scope: createdScope, createdScopes: scopesCreated(alongWith: createdScope), nextIndex: 0))
				}
			} else {
				path.removeLast()
				// The scope the search starts from is the one being analyzed.
				if !path.isEmpty {
					unanalyzedScopes.append(pathScope)
				}
			}
		}
		return unanalyzedScopes
	}

	/// A constant or lazily instantiated `@Instantiated` dependency whose type has `@Forwarded` properties, and
	/// the type that declares it.
	private struct ForwardedPropertyError {
		let parent: TypeDescription
		let error: DependencyTreeGeneratorError
	}

	/// The error for a constant or lazily instantiated `@Instantiated` dependency on `parent` whose `instantiable`
	/// has `@Forwarded` properties, or `nil` when the dependency is valid.
	func forwardedPropertyError(
		for dependency: Dependency,
		instantiable: Instantiable,
		parent: Instantiable,
	) -> DependencyTreeGeneratorError? {
		guard dependency.property.propertyType.isConstant || dependency.property.propertyType.isLazilyInstantiated else { return nil }
		let forwardedDependencies = instantiable.dependencies.filter(\.isForwarded)
		guard !forwardedDependencies.isEmpty else { return nil }
		// The suggestion is `Sendable` when the property’s wrapper is, or when `parent`’s declaration lists `Sendable`,
		// which requires each stored property to be. Any other conformance may make `parent` `Sendable` in a way only
		// another declaration says, which a module’s generation may not read, so the advice then names both forms.
		let isSendable = dependency.property.propertyType.isSendable || parent.conformanceListNamesSendable
		func suggestedPropertyType(isSendable: Bool) -> TypeDescription {
			Self.instantiatorType(
				building: instantiable,
				forwarding: forwardedDependencies.map(\.property),
				for: dependency,
				isSendable: isSendable,
			)
		}
		return .instantiableHasForwardedProperty(.init(
			dependency: dependency,
			instantiable: instantiable,
			suggestedPropertyType: suggestedPropertyType(isSendable: isSendable),
			sendableAlternative: isSendable || !parent.conformanceListNamesOtherTypes ? nil : suggestedPropertyType(isSendable: true),
			forwardedDeclarations: forwardedDependencies.map {
				DependencyTreeGeneratorError.LocatedProperty(property: $0.property, declarationLocation: $0.declarationLocation)
			},
			parent: parent.concreteInstantiable,
		))
	}

	/// The type with which `dependency`, a constant or lazily instantiated `@Instantiated` property, can instead
	/// build `instantiable` when it is asked for, which `instantiable`’s `@Forwarded` properties require:
	/// `Instantiator<Child>` for `child: Child` or `child: LazilyInstantiated<Child>`. `fulfilledByType` cannot
	/// be used on an `Instantiator`, so a property with that argument gets an `ErasedInstantiator` of the type the
	/// property declares, such as `ErasedInstantiator<String, AnyChild>` for `child: AnyChild` when `Child`
	/// forwards a `String`. The forwarded properties are spelled out rather than as `Child.ForwardedProperties`,
	/// which the module that declares the property may not be able to see. The suggestion is `Sendable` when
	/// `isSendable`, and the type an erased instantiator builds is not optional.
	private static func instantiatorType(
		building instantiable: Instantiable,
		forwarding forwardedProperties: [Property],
		for dependency: Dependency,
		isSendable: Bool,
	) -> TypeDescription {
		if case .instantiated(fulfillingTypeDescription: .some, _) = dependency.source {
			let declaredType = dependency.property.typeDescription.unwrapped
			let builtType = declaredType.lazilyInstantiatedInstanceType?.unwrapped ?? declaredType
			return .simple(
				name: isSendable ? Dependency.sendableErasedInstantiatorType : Dependency.erasedInstantiatorType,
				generics: [
					forwardedProperties.asForwardedPropertiesTypeDescription,
					builtType,
				],
			)
		} else {
			return .simple(
				name: isSendable ? Dependency.sendableInstantiatorType : Dependency.instantiatorType,
				generics: [instantiable.concreteInstantiable],
			)
		}
	}

	/// The lazily instantiated properties on a cycle as they are declared, outermost first, for the diagnostic.
	///
	/// - Parameters:
	///   - declaredProperty: The dependency that closes the cycle, as it is declared.
	///   - validatedPropertiesInCycle: The properties on the cycle as cycle validation sees them, innermost first.
	///   - lazilyInstantiatedDeclarations: The lazily instantiated properties being instantiated, keyed by the
	///     constant each is validated as.
	///   - receivedProperties: The dependencies received between the outermost property and the one that
	///     closes the cycle, as they are declared.
	static func lazilyInstantiatedProperties(
		closingCycleWith declaredProperty: Property,
		validatedPropertiesInCycle: some Collection<Property>,
		lazilyInstantiatedDeclarations: [Property: Property],
		receivedProperties: [Property] = [],
	) -> [Property] {
		var listedProperties = Set<Property>()
		return (validatedPropertiesInCycle.reversed().compactMap { lazilyInstantiatedDeclarations[$0] } + receivedProperties + [declaredProperty])
			.filter { $0.propertyType.isLazilyInstantiated && listedProperties.insert($0).inserted }
	}
}
