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

import SafeDICore

/// `unnormalizedInstantiables` with each dependency's property type, `fulfilledByType:` type, and alias
/// `ofType:` type, and each hand-written mock's argument and return types, qualified as the compiler resolves
/// them among the types the instantiables fulfill, so a nested type wins over a top-level type of the same
/// name. The initializer's arguments are mapped by the qualified property types. See
/// `TypeDescription.qualifyingInstantiatedType(within:amongInstantiableTypes:)`.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
func normalizingInstantiableTypes(of unnormalizedInstantiables: [Instantiable]) -> [Instantiable] {
	let instantiableTypes = Set(unnormalizedInstantiables.flatMap(\.instantiableTypes))
	return unnormalizedInstantiables.map { unnormalizedInstantiable in
		func normalized(_ typeDescription: TypeDescription) -> TypeDescription? {
			typeDescription.qualifyingInstantiatedType(
				within: unnormalizedInstantiable.concreteInstantiable,
				amongInstantiableTypes: instantiableTypes,
			)
		}
		let unnormalizedToNormalizedTypeMap = unnormalizedInstantiable.dependencies.reduce(
			into: [TypeDescription: TypeDescription](),
		) { partialResult, nextDependency in
			if let bestTypeDescription = normalized(nextDependency.property.typeDescription) {
				partialResult[nextDependency.property.typeDescription] = bestTypeDescription
			}
		}

		let normalizedDependencies = unnormalizedInstantiable.dependencies.map { dependency in
			// The type that fulfills an instantiated or aliased dependency is written where the property is.
			let normalizedSource: Dependency.Source? = switch dependency.source {
			case let .instantiated(fulfillingTypeDescription, erasedToConcreteExistential):
				fulfillingTypeDescription.flatMap(normalized).map {
					.instantiated(
						fulfillingTypeDescription: $0,
						erasedToConcreteExistential: erasedToConcreteExistential,
					)
				}
			case let .aliased(fulfillingProperty, erasedToConcreteExistential, onlyIfAvailable):
				normalized(fulfillingProperty.typeDescription).map {
					.aliased(
						fulfillingProperty: fulfillingProperty.withUpdatedTypeDescription($0),
						erasedToConcreteExistential: erasedToConcreteExistential,
						onlyIfAvailable: onlyIfAvailable,
					)
				}
			case .forwarded, .received:
				nil
			}
			let normalizedTypeDescription = unnormalizedToNormalizedTypeMap[dependency.property.typeDescription]
			guard normalizedSource != nil || normalizedTypeDescription != nil else {
				// Default to what was in the code – we'll probably error later
				return dependency
			}
			return Dependency(
				property: normalizedTypeDescription.map(dependency.property.withUpdatedTypeDescription) ?? dependency.property,
				source: normalizedSource ?? dependency.source,
				declarationLocation: dependency.declarationLocation,
				identifierRange: dependency.identifierRange,
				typeAnnotationRange: dependency.typeAnnotationRange,
				bareAttributeRange: dependency.bareAttributeRange,
			)
		}
		let normalizedInitializer = unnormalizedInstantiable.initializer?.mapArguments {
			$0.withUpdatedTypeDescription(unnormalizedToNormalizedTypeMap[$0.typeDescription, default: $0.typeDescription])
		}
		let normalizedAdditionalInstantiables = unnormalizedInstantiable.instantiableTypes.dropFirst().map {
			if let enclosingType = unnormalizedInstantiable.concreteInstantiable.popNested,
			   let bestTypeDescription = TypeDescription.nestedOptions(
			   	referencedType: $0,
			   	within: enclosingType,
			   ).first(where: { instantiableTypes.contains($0) })
			{
				bestTypeDescription
			} else {
				// Default to what was in the code – we'll probably error later
				$0
			}
		}
		var normalized = Instantiable(
			instantiableType: unnormalizedInstantiable.concreteInstantiable,
			isRoot: unnormalizedInstantiable.isRoot,
			initializer: normalizedInitializer,
			additionalInstantiables: normalizedAdditionalInstantiables,
			dependencies: normalizedDependencies,
			declarationType: unnormalizedInstantiable.declarationType,
			mockAttributes: unnormalizedInstantiable.mockAttributes,
			generateMock: unnormalizedInstantiable.generateMock,
			mockOnly: unnormalizedInstantiable.mockOnly,
			// A hand-written mock's arguments are matched to dependencies by type. A `mockOnly` declaration has no
			// dependencies of its own to map them by, and its mock is matched to those of the declaration it merges
			// into, so each argument's type is qualified on its own.
			mockInitializer: unnormalizedInstantiable.mockInitializer?.mapArguments {
				$0.withUpdatedTypeDescription(normalized($0.typeDescription) ?? $0.typeDescription)
			},
			// The macro requires a hand-written mock to return `Self` or the type's name as its declaration spells
			// it, so a nested type's mock returns its unqualified name.
			mockReturnType: unnormalizedInstantiable.mockReturnType.map { normalized($0) ?? $0 },
			customMockName: unnormalizedInstantiable.customMockName,
			mockDeclarationLocation: unnormalizedInstantiable.mockDeclarationLocation,
			declarationLocation: unnormalizedInstantiable.declarationLocation,
		)
		normalized.sourceFilePath = unnormalizedInstantiable.sourceFilePath
		return normalized
	}
}

/// The `@Instantiable` declaration that fulfills each type, merging a `mockOnly` declaration's mock into the
/// production declaration for the same type. Throws when two production declarations fulfill one type, or
/// when a type has more than one hand-written mock.
func resolveSafeDIFulfilledTypes(instantiables: [Instantiable]) throws -> [TypeDescription: Instantiable] {
	// Errors cite every declaration claiming the type rather than the pair that collided: a merged entry
	// no longer knows which declaration it came from, and the pair would depend on collection order.
	func productionDeclarationLocations(fulfilling instantiableType: TypeDescription) -> [Dependency.DeclarationLocation?] {
		instantiables
			.filter { !$0.mockOnly && $0.instantiableTypes.contains(instantiableType) }
			.map(\.declarationLocation)
	}
	func mockProviderDeclarationLocations(fulfilling instantiableType: TypeDescription) -> [Dependency.DeclarationLocation?] {
		instantiables
			.filter { ($0.mockOnly || $0.mockInitializer != nil) && $0.instantiableTypes.contains(instantiableType) }
			.map(\.declarationLocation)
	}
	var typeDescriptionToFulfillingInstantiableMap = [TypeDescription: Instantiable]()
	// Track types that have already had a mockOnly merged in, so a second
	// mockOnly is rejected even after the merged entry appears non-mockOnly.
	var typesWithMockOnlyMerge = Set<TypeDescription>()
	// Every type fulfilled more than once is reported, in source order, so which is reported never depends on the
	// order of the modules and files. A type is no longer resolved once it has an error.
	var errorByInstantiableType = [TypeDescription: CollectInstantiablesError]()
	for instantiable in instantiables {
		for instantiableType in instantiable.instantiableTypes where errorByInstantiableType[instantiableType] == nil {
			if let existing = typeDescriptionToFulfillingInstantiableMap[instantiableType] {
				// Allow one mockOnly and one non-mockOnly for the same type.
				switch (existing.mockOnly, instantiable.mockOnly) {
				case (true, true):
					errorByInstantiableType[instantiableType] = .duplicateMockProvider(instantiableType, declaredAt: mockProviderDeclarationLocations(fulfilling: instantiableType))
				case (false, true):
					guard !typesWithMockOnlyMerge.contains(instantiableType) else {
						errorByInstantiableType[instantiableType] = .duplicateMockProvider(instantiableType, declaredAt: mockProviderDeclarationLocations(fulfilling: instantiableType))
						continue
					}
					typesWithMockOnlyMerge.insert(instantiableType)
					if existing.concreteInstantiable == instantiable.concreteInstantiable {
						// Same concrete type: two hand-written mocks is ambiguous.
						guard existing.mockInitializer == nil else {
							errorByInstantiableType[instantiableType] = .duplicateMockProvider(instantiableType, declaredAt: mockProviderDeclarationLocations(fulfilling: instantiableType))
							continue
						}
						// Only merge if the mockOnly's return type is compatible
						// with this slot. Check against instantiableType (the key)
						// so a mock returning ServiceProtocol merges for the
						// ServiceProtocol slot but not the MyService slot.
						if instantiable.mockReturnTypeIsCompatible(withPropertyType: instantiableType) {
							typeDescriptionToFulfillingInstantiableMap[instantiableType] = existing.mergedWithMockProvider(instantiable)
						}
					} else {
						// Different concrete types: non-mockOnly already holds the
						// slot, so the mockOnly is not registered here.
					}
				case (true, false):
					typesWithMockOnlyMerge.insert(instantiableType)
					if existing.concreteInstantiable == instantiable.concreteInstantiable {
						// Same concrete type: two hand-written mocks is ambiguous.
						guard instantiable.mockInitializer == nil else {
							errorByInstantiableType[instantiableType] = .duplicateMockProvider(instantiableType, declaredAt: mockProviderDeclarationLocations(fulfilling: instantiableType))
							continue
						}
						// Only merge if the mockOnly's return type is compatible
						// with this slot.
						if existing.mockReturnTypeIsCompatible(withPropertyType: instantiableType) {
							typeDescriptionToFulfillingInstantiableMap[instantiableType] = instantiable.mergedWithMockProvider(existing)
						} else {
							// mockOnly's mock returns incompatible type — replace
							// with production entry (no mock merge).
							typeDescriptionToFulfillingInstantiableMap[instantiableType] = instantiable
						}
					} else {
						// Different concrete types: non-mockOnly wins the slot.
						typeDescriptionToFulfillingInstantiableMap[instantiableType] = instantiable
					}
				case (false, false):
					errorByInstantiableType[instantiableType] = .foundDuplicateInstantiable(instantiableType, declaredAt: productionDeclarationLocations(fulfilling: instantiableType))
				}
			} else {
				typeDescriptionToFulfillingInstantiableMap[instantiableType] = instantiable
			}
		}
	}
	guard errorByInstantiableType.isEmpty else {
		throw CollectInstantiablesError.independentErrors(Array(errorByInstantiableType.values))
	}

	// Propagate merged mock info to sibling entries: when a mockOnly merged
	// into one key for a concreteInstantiable, other keys for the same
	// concreteInstantiable (from fulfillingAdditionalTypes) may still lack
	// the mock info. Copy it so all entries are consistent.
	// Only propagate when the mock return type is compatible with the
	// target entry's concrete type — a mock returning ServiceProtocol
	// should not spread to the MyService slot.
	var mockProviderByConcreteType = [TypeDescription: Instantiable]()
	for instantiable in typeDescriptionToFulfillingInstantiableMap.values
		where !instantiable.mockOnly && instantiable.mockInitializer != nil
	{
		mockProviderByConcreteType[instantiable.concreteInstantiable] = instantiable
	}
	for (typeDescription, instantiable) in typeDescriptionToFulfillingInstantiableMap {
		if !instantiable.mockOnly,
		   instantiable.mockInitializer == nil,
		   let mockProvider = mockProviderByConcreteType[instantiable.concreteInstantiable],
		   mockProvider.mockReturnTypeIsCompatible(withPropertyType: instantiable.concreteInstantiable)
		{
			typeDescriptionToFulfillingInstantiableMap[typeDescription] = instantiable.mergedWithMockProvider(mockProvider)
		}
	}

	return typeDescriptionToFulfillingInstantiableMap
}

private enum CollectInstantiablesError: SourceLocatedError {
	case foundDuplicateInstantiable(TypeDescription, declaredAt: [Dependency.DeclarationLocation?])
	case duplicateMockProvider(TypeDescription, declaredAt: [Dependency.DeclarationLocation?])
	/// The errors of different types, each reported as it would be alone, in source order.
	case independentErrors([CollectInstantiablesError])

	var sourceDiagnostics: [SourceDiagnostic] {
		switch self {
		case let .foundDuplicateInstantiable(duplicateInstantiable, declaredAt):
			Self.sourceDiagnostics(
				message: "Found multiple @\(InstantiableVisitor.macroName) types or extensions that fulfill `\(duplicateInstantiable.asSource)`. Each type can be fulfilled by only one @\(InstantiableVisitor.macroName) declaration, across all modules. Keep one, and remove `\(duplicateInstantiable.asSource)` from the others’ `fulfillingAdditionalTypes` or remove their @\(InstantiableVisitor.macroName).",
				declaredAt: declaredAt,
			)
		case let .duplicateMockProvider(duplicateInstantiable, declaredAt):
			Self.sourceDiagnostics(
				message: "Found multiple hand-written mocks for `\(duplicateInstantiable.asSource)`. A type can have at most one, on its production declaration or on a single `mockOnly: true` declaration. Remove all but one.",
				declaredAt: declaredAt,
			)
		case let .independentErrors(errors):
			SourceDiagnostic.joiningInSourceOrder(errors.map(\.sourceDiagnostics))
		}
	}

	/// An error at each of `declarationLocations`, in source order, so the output does not depend on collection order.
	private static func sourceDiagnostics(message: String, declaredAt declarationLocations: [Dependency.DeclarationLocation?]) -> [SourceDiagnostic] {
		declarationLocations
			.map { declarationLocation in
				SourceDiagnostic(
					severity: .error,
					location: declarationLocation,
					message: message,
				)
			}
			.sorted(by: SourceDiagnostic.precedesInSourceOrder)
	}
}
