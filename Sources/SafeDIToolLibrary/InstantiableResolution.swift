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

/// `unnormalizedInstantiables` with each type a declaration spells – each dependency's property type, `fulfilledByType:`
/// type, and alias `ofType:` type, the arguments of its initializer, other initializers, and hand-written mock, and that
/// mock's return type – qualified as the compiler resolves it where the declaration spells it, so generated code outside
/// the declaration names the same type. The type a dependency instantiates is qualified among the types the
/// instantiables fulfill, so a nested type wins over a top-level type of the same name
/// (`TypeDescription.qualifyingInstantiatedType(within:amongInstantiableTypes:searchingTypesEnclosingIt:namesOfNestedInstantiableTypes:)`);
/// then each outermost name is qualified among those types and `plainTypeDeclarations`
/// (`TypeAccessProof.NestedTypeQualifier`), so a type nested in the declaration's type, or in a type enclosing it, is
/// qualified though it is not `@Instantiable`.
/// - Parameter plainTypeDeclarations: The plain type declarations of the modules whose declarations
///   `unnormalizedInstantiables` holds, each with the module that declares it.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
func normalizingInstantiableTypes(of unnormalizedInstantiables: [Instantiable], plainTypeDeclarations: [PlainTypeDeclaration]) -> [Instantiable] {
	let instantiableTypes = Set(unnormalizedInstantiables.flatMap(\.instantiableTypes))
	let nestedTypeQualifier = TypeAccessProof.NestedTypeQualifier(instantiables: unnormalizedInstantiables, plainTypeDeclarations: plainTypeDeclarations)
	return unnormalizedInstantiables.map { unnormalizedInstantiable in
		let mentioningModule = TypeAccessProof.MentioningModule.declaration(unnormalizedInstantiable)
		// An extension-based declaration's members are written in an extension at file scope.
		let searchingTypesEnclosingIt = !unnormalizedInstantiable.declarationType.isExtension
		/// The instantiated type of `typeDescription` qualified among the instantiable types, or `nil` when no option
		/// of it is one or the option is the type as written.
		func qualifyingInstantiatedType(_ typeDescription: TypeDescription) -> TypeDescription? {
			nestedTypeQualifier.qualifyingInstantiatedType(
				in: typeDescription,
				writtenWithin: unnormalizedInstantiable.concreteInstantiable,
				searchingTypesEnclosingIt: searchingTypesEnclosingIt,
			)
			// Every option but the type as written nests a name the type as written does not, so an option `==` finds
			// the same is the type as written, which is kept rather than rebuilt.
			.flatMap { $0 == typeDescription ? nil : $0 }
		}
		/// `typeDescription`, which a member of the declaration spells, qualified as the compiler resolves it there, or
		/// `nil` when that qualifies nothing, so that what spells it is kept rather than rebuilt.
		func normalized(_ typeDescription: TypeDescription) -> TypeDescription? {
			let instantiatedTypeQualified = qualifyingInstantiatedType(typeDescription)
			return nestedTypeQualifier.qualifyingNestedTypes(
				in: instantiatedTypeQualified ?? typeDescription,
				writtenWithin: unnormalizedInstantiable.concreteInstantiable,
				searchingTypesEnclosingIt: searchingTypesEnclosingIt,
				mentionedFrom: mentioningModule,
			) ?? instantiatedTypeQualified
		}
		/// `argument` with its type normalized, as its declaration spells it.
		func normalizedArgument(_ argument: Initializer.Argument) -> Initializer.Argument {
			normalized(argument.typeDescription).map(argument.withUpdatedTypeDescription) ?? argument
		}

		let normalizedDependencies = unnormalizedInstantiable.dependencies.map { dependency in
			// The type that fulfills an instantiated or aliased dependency is written where the property is.
			let normalizedSource: Dependency.Source? = switch dependency.source {
			case let .instantiated(fulfillingTypeDescription, erasedToConcreteExistential):
				// `fulfilledByType:` names an `@Instantiable` type, or the dependency is reported unfulfillable.
				fulfillingTypeDescription.flatMap(qualifyingInstantiatedType).map {
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
			let normalizedPropertyType = normalized(dependency.property.typeDescription)
			guard normalizedSource != nil || normalizedPropertyType != nil else {
				// Normalization qualifies nothing the dependency spells.
				return dependency
			}
			return Dependency(
				property: normalizedPropertyType.map(dependency.property.withUpdatedTypeDescription) ?? dependency.property,
				source: normalizedSource ?? dependency.source,
				declarationLocation: dependency.declarationLocation,
				identifierRange: dependency.identifierRange,
				typeAnnotationRange: dependency.typeAnnotationRange,
				bareAttributeRange: dependency.bareAttributeRange,
			)
		}
		// Each argument is qualified on its own, which qualifies a dependency's argument as its property: the same type
		// written in the same place.
		let normalizedInitializer = unnormalizedInstantiable.initializer?.mapArguments(normalizedArgument)
		let normalizedAdditionalInstantiables = unnormalizedInstantiable.instantiableTypes.dropFirst().map {
			if let enclosingType = unnormalizedInstantiable.concreteInstantiable.popNested, !unnormalizedInstantiable.declarationType.isExtension {
				// `fulfillingAdditionalTypes:` is written in the macro's attribute, outside the type, in the types
				// enclosing it; on an extension, at file scope, where every name is as written.
				let qualifiedInstantiableType = TypeDescription.nestedOptions(
					referencedType: $0,
					within: enclosingType,
				).first(where: { instantiableTypes.contains($0) }) ?? $0
				return nestedTypeQualifier.qualifyingNestedTypes(
					in: qualifiedInstantiableType,
					writtenWithin: enclosingType,
					searchingTypesEnclosingIt: true,
					mentionedFrom: mentioningModule,
				) ?? qualifiedInstantiableType
			} else {
				// A top-level type's attribute is written at file scope, where every name is as written.
				return $0
			}
		}
		var normalizedInstantiable = Instantiable(
			instantiableType: unnormalizedInstantiable.concreteInstantiable,
			isRoot: unnormalizedInstantiable.isRoot,
			generatesDependencyTree: unnormalizedInstantiable.generatesDependencyTree,
			initializer: normalizedInitializer,
			// An initializer SafeDI never constructs the type with is compared with a generated tier's parameters by
			// type, so each argument's type is qualified on its own, as a hand-written mock's are: a nested
			// pass-through type it names unqualified must match the qualified parameter.
			otherInitializers: unnormalizedInstantiable.otherInitializers.compactMap { $0.mapArguments(normalizedArgument) },
			additionalInstantiables: normalizedAdditionalInstantiables,
			dependencies: normalizedDependencies,
			declarationType: unnormalizedInstantiable.declarationType,
			access: unnormalizedInstantiable.access,
			enclosingTypeAccess: unnormalizedInstantiable.enclosingTypeAccess,
			enclosingExtensionAccess: unnormalizedInstantiable.enclosingExtensionAccess,
			generatedInitializerAttributes: unnormalizedInstantiable.generatedInitializerAttributes,
			mockAttributes: unnormalizedInstantiable.mockAttributes,
			declarationIsolation: unnormalizedInstantiable.declarationIsolation,
			generateMock: unnormalizedInstantiable.generateMock,
			mockGenerationArgumentRange: unnormalizedInstantiable.mockGenerationArgumentRange,
			mockOnly: unnormalizedInstantiable.mockOnly,
			// A hand-written mock's arguments are matched to dependencies by type. A `mockOnly` declaration has no
			// dependencies of its own to map them by, and its mock is matched to those of the declaration it merges
			// into, so each argument's type is qualified on its own.
			mockInitializer: unnormalizedInstantiable.mockInitializer?.mapArguments(normalizedArgument),
			// The macro requires a hand-written mock to return `Self` or the type's name as its declaration spells
			// it, so a nested type's mock returns its unqualified name.
			mockReturnType: unnormalizedInstantiable.mockReturnType.map { normalized($0) ?? $0 },
			customMockName: unnormalizedInstantiable.customMockName,
			mockDeclarationLocation: unnormalizedInstantiable.mockDeclarationLocation,
			mockDeclarationAccess: unnormalizedInstantiable.mockDeclarationAccess,
			mockDeclarationModuleName: unnormalizedInstantiable.mockDeclarationModuleName,
			mockDeclarationPackageName: unnormalizedInstantiable.mockDeclarationPackageName,
			declarationLocation: unnormalizedInstantiable.declarationLocation,
			moduleName: unnormalizedInstantiable.moduleName,
			packageName: unnormalizedInstantiable.packageName,
		)
		normalizedInstantiable.sourceFilePath = unnormalizedInstantiable.sourceFilePath
		normalizedInstantiable.isInsideCompilerDecidedBlock = unnormalizedInstantiable.isInsideCompilerDecidedBlock
		return normalizedInstantiable
	}
}

/// The `@Instantiable` declaration that fulfills each type, merging a `mockOnly` declaration's mock into the
/// production declaration for the same type. Throws when two production declarations fulfill one type, or
/// when a type has more than one hand-written mock.
func resolveSafeDIFulfilledTypes(instantiables: [Instantiable]) throws -> [TypeDescription: Instantiable] {
	// Errors cite every declaration claiming the type rather than the pair that collided: a merged entry
	// no longer knows which declaration it came from, and the pair would depend on collection order.
	func productionDeclarations(fulfilling instantiableType: TypeDescription) -> [Instantiable] {
		instantiables.filter { !$0.mockOnly && $0.instantiableTypes.contains(instantiableType) }
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
					errorByInstantiableType[instantiableType] = .duplicate(of: instantiableType, declaredBy: productionDeclarations(fulfilling: instantiableType))
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
	/// Two or more production declarations fulfill the type. `isEachInsideCompilerDecidedBlock` says whether each is
	/// inside an `#if` block whose condition only the compiler decides, so that the compiler may compile only one. The
	/// flag does not say whether the blocks exclude one another (two files may each guard the type with `#if os(iOS)`),
	/// so the message offers both remedies.
	case foundDuplicateInstantiable(TypeDescription, declaredAt: [Dependency.DeclarationLocation?], isEachInsideCompilerDecidedBlock: Bool)
	/// Each declaration is a type of this name, and at least one is in a module SafeDI does not know, which may or may not
	/// be another's. The message offers renaming, for types that have nothing to do with each other, beside keeping one.
	case foundTypesOfOneNameInUnknownModules(TypeDescription, declaredAt: [Dependency.DeclarationLocation?], isEachInsideCompilerDecidedBlock: Bool)
	/// Each of the two or more modules `moduleNames` lists, in sorted order, declares a type of this name, and those
	/// `repeatingModuleNames` lists, in sorted order, declare it more than once.
	/// `isEachInsideCompilerDecidedBlock` is as for `foundDuplicateInstantiable`: SafeDI cannot tell one type split by
	/// platform across modules from two types that have nothing to do with each other, so the message offers both remedies.
	case foundTypesOfOneNameInSeveralModules(TypeDescription, moduleNames: [String], repeatingModuleNames: [String], declaredAt: [Dependency.DeclarationLocation?], isEachInsideCompilerDecidedBlock: Bool)
	/// At least one declaration is an extension or a `fulfillingAdditionalTypes` claim of this name, and the declarations are
	/// in the two or more modules `moduleNames` lists, in sorted order, or, when `moduleNames` is `nil`, at least one is in a
	/// module SafeDI does not know. SafeDI reads only `@Instantiable` declarations here, so it cannot tell one type of this
	/// name from a type of the name in each module, and the message offers renaming beside keeping one. Those
	/// `repeatingModuleNames` lists, in sorted order, fulfill it more than once.
	case foundClaimsOfOneName(TypeDescription, moduleNames: [String]?, repeatingModuleNames: [String], declaredAt: [Dependency.DeclarationLocation?], isEachInsideCompilerDecidedBlock: Bool)
	/// One declaration fulfills this type twice: its `fulfillingAdditionalTypes` names its own type, or repeats an entry.
	case foundRepeatedClaim(TypeDescription, declaredAt: [Dependency.DeclarationLocation?])
	case duplicateMockProvider(TypeDescription, declaredAt: [Dependency.DeclarationLocation?])
	/// The errors of different types, each reported as it would be alone, in source order.
	case independentErrors([CollectInstantiablesError])

	/// The error for `declarations`, two or more production declarations that fulfill `type`.
	static func duplicate(of type: TypeDescription, declaredBy declarations: [Instantiable]) -> CollectInstantiablesError {
		let isEachInsideCompilerDecidedBlock = declarations.allSatisfy(\.isInsideCompilerDecidedBlock)
		let declaredAt = declarations.map(\.declarationLocation)
		let moduleNames = declarations.compactMap(\.moduleName)
		// Sorted, so the message does not depend on the order the modules were read in.
		let distinctModuleNames = Set(moduleNames).sorted()
		let isEachInKnownModule = moduleNames.count == declarations.count
		guard declarations.count > 1 else {
			return .foundRepeatedClaim(type, declaredAt: declaredAt)
		}
		// A module's own duplicates are one type, so keeping one is the remedy.
		guard !isEachInKnownModule || distinctModuleNames.count > 1 else {
			return .foundDuplicateInstantiable(type, declaredAt: declaredAt, isEachInsideCompilerDecidedBlock: isEachInsideCompilerDecidedBlock)
		}
		let repeatingModuleNames = distinctModuleNames.filter { moduleName in
			moduleNames.count(where: { $0 == moduleName }) > 1
		}
		guard declarations.allSatisfy({ !$0.declarationType.isExtension && $0.concreteInstantiable == type }) else {
			return .foundClaimsOfOneName(
				type,
				moduleNames: isEachInKnownModule ? distinctModuleNames : nil,
				repeatingModuleNames: repeatingModuleNames,
				declaredAt: declaredAt,
				isEachInsideCompilerDecidedBlock: isEachInsideCompilerDecidedBlock,
			)
		}
		guard isEachInKnownModule else {
			return .foundTypesOfOneNameInUnknownModules(type, declaredAt: declaredAt, isEachInsideCompilerDecidedBlock: isEachInsideCompilerDecidedBlock)
		}
		return .foundTypesOfOneNameInSeveralModules(
			type,
			moduleNames: distinctModuleNames,
			repeatingModuleNames: repeatingModuleNames,
			declaredAt: declaredAt,
			isEachInsideCompilerDecidedBlock: isEachInsideCompilerDecidedBlock,
		)
	}

	var sourceDiagnostics: [SourceDiagnostic] {
		switch self {
		case let .foundDuplicateInstantiable(duplicateInstantiable, declaredAt, isEachInsideCompilerDecidedBlock):
			Self.sourceDiagnostics(
				message: "Found multiple @\(InstantiableVisitor.macroName) types or extensions that fulfill `\(duplicateInstantiable.asSource)`. "
					+ (isEachInsideCompilerDecidedBlock
						? "Each is declared inside an `#if` that only the compiler decides, such as `#if os(iOS)`, and SafeDI reads every clause. If no build compiles more than one of them, fulfill `\(duplicateInstantiable.asSource)` with one @\(InstantiableVisitor.macroName) declaration outside the `#if`, and put the platform difference \(Self.placeOfPlatformDifference). Otherwise, keep one, and remove `\(duplicateInstantiable.asSource)` from the others’ `fulfillingAdditionalTypes` or remove their @\(InstantiableVisitor.macroName)."
						: "Each type can be fulfilled by only one @\(InstantiableVisitor.macroName) declaration, across all modules. Keep one, and remove `\(duplicateInstantiable.asSource)` from the others’ `fulfillingAdditionalTypes` or remove their @\(InstantiableVisitor.macroName)."),
				declaredAt: declaredAt,
			)
		case let .foundTypesOfOneNameInUnknownModules(type, declaredAt, isEachInsideCompilerDecidedBlock):
			Self.sourceDiagnostics(
				message: "Found multiple @\(InstantiableVisitor.macroName) types or extensions that fulfill `\(type.asSource)`. "
					+ (isEachInsideCompilerDecidedBlock
						? "Each is declared inside an `#if` that only the compiler decides, such as `#if os(iOS)`, and SafeDI reads every clause. If they are one type that differs by platform, fulfill `\(type.asSource)` with one @\(InstantiableVisitor.macroName) declaration outside the `#if`, and put the platform difference \(Self.placeOfPlatformDifference). If they are different types, \(Self.renameRemedy(forTypeCount: declaredAt.count)). Otherwise, keep one, and remove the others’ @\(InstantiableVisitor.macroName)."
						: "Each type can be fulfilled by only one @\(InstantiableVisitor.macroName) declaration, across all modules. If they are different types, \(Self.renameRemedy(forTypeCount: declaredAt.count)). If they are one type, keep one, and remove the others’ @\(InstantiableVisitor.macroName)."),
				declaredAt: declaredAt,
			)
		case let .foundTypesOfOneNameInSeveralModules(type, moduleNames, repeatingModuleNames, declaredAt, isEachInsideCompilerDecidedBlock):
			Self.sourceDiagnostics(
				message: Self.severalModulesMessage(
					for: type,
					moduleNames: moduleNames,
					repeatingModuleNames: repeatingModuleNames,
					isEachInsideCompilerDecidedBlock: isEachInsideCompilerDecidedBlock,
				),
				declaredAt: declaredAt,
			)
		case let .foundClaimsOfOneName(type, moduleNames, repeatingModuleNames, declaredAt, isEachInsideCompilerDecidedBlock):
			Self.sourceDiagnostics(
				message: Self.claimsMessage(
					for: type,
					moduleNames: moduleNames,
					repeatingModuleNames: repeatingModuleNames,
					declarationCount: declaredAt.count,
					isEachInsideCompilerDecidedBlock: isEachInsideCompilerDecidedBlock,
				),
				declaredAt: declaredAt,
			)
		case let .foundRepeatedClaim(type, declaredAt):
			Self.sourceDiagnostics(
				message: "`fulfillingAdditionalTypes` repeats `\(type.asSource)`, which this @\(InstantiableVisitor.macroName) declaration already fulfills. Remove the repeat.",
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

	private static let nameRule = "SafeDI tells @\(InstantiableVisitor.macroName) types apart by name across every module a run reads"
	private static let placeOfPlatformDifference = "inside its body or its `\(InstantiableVisitor.instantiateMethodName)(…)` method"

	private static func severalModulesMessage(for type: TypeDescription, moduleNames: [String], repeatingModuleNames: [String], isEachInsideCompilerDecidedBlock: Bool) -> String {
		let declaredIn = "`\(type.asSource)` is declared in modules \(listed(moduleNames))"
			+ (repeatingModuleNames.isEmpty ? ". " : ", and more than once in \(listed(repeatingModuleNames)). ")
		let reason = nameRule + (isEachInsideCompilerDecidedBlock ? ", and reads every clause of an `#if` that only the compiler decides, such as `#if os(iOS)`. " : ". ")
		// A module's duplicates share a name whichever other module is renamed, so they are resolved first.
		let rename = renameRemedy(forTypeCount: moduleNames.count)
		let remedy = repeatingModuleNames.isEmpty
			? rename
			: "declare it once in \(repeatingModuleNames.count == 1 ? "" : "each of ")\(listed(repeatingModuleNames)), with any platform difference \(placeOfPlatformDifference), then \(rename)"
		return declaredIn + reason + (isEachInsideCompilerDecidedBlock
			? "If they are one type that differs by platform, declare it with one @\(InstantiableVisitor.macroName) declaration, in one of these modules and outside the `#if`, and put the platform difference \(placeOfPlatformDifference). If they are different types, \(remedy)."
			: "\(remedy.prefix(1).uppercased())\(remedy.dropFirst()).")
	}

	private static func claimsMessage(for type: TypeDescription, moduleNames: [String]?, repeatingModuleNames: [String], declarationCount: Int, isEachInsideCompilerDecidedBlock: Bool) -> String {
		let declaredIn = moduleNames.map { moduleNames in
			", in modules \(listed(moduleNames))" + (repeatingModuleNames.isEmpty ? "" : ", and more than once in \(listed(repeatingModuleNames))")
		} ?? ""
		// A module's own repeats fulfill the name whichever other module renames it, so they are resolved first.
		let rename = renameRemedy(forTypeCount: moduleNames?.count ?? declarationCount)
		let remedy = repeatingModuleNames.isEmpty
			? rename
			: "fulfill it once in \(repeatingModuleNames.count == 1 ? "" : "each of ")\(listed(repeatingModuleNames)), with any platform difference \(placeOfPlatformDifference), then \(rename)"
		let keepOne = "keep one, and remove `\(type.asSource)` from the others’ `fulfillingAdditionalTypes` or remove their @\(InstantiableVisitor.macroName)."
		return "Found multiple @\(InstantiableVisitor.macroName) types or extensions that fulfill `\(type.asSource)`\(declaredIn). " + (isEachInsideCompilerDecidedBlock
			? "Each is declared inside an `#if` that only the compiler decides, such as `#if os(iOS)`, and SafeDI reads every clause. If `\(type.asSource)` names one type that differs by platform, fulfill `\(type.asSource)` with one @\(InstantiableVisitor.macroName) declaration outside the `#if`, and put the platform difference \(placeOfPlatformDifference). If it names different types, \(remedy). Otherwise, \(keepOne)"
			: "Each type can be fulfilled by only one @\(InstantiableVisitor.macroName) declaration, across all modules. If `\(type.asSource)` names different types, \(remedy). If it names one type, \(keepOne)")
	}

	/// How to tell apart `typeCount` types, two or more, that share a name, as the end of a sentence without its period.
	private static func renameRemedy(forTypeCount typeCount: Int) -> String {
		typeCount == 2 ? "rename one" : "rename all but one"
	}

	/// `moduleNames`, one or more, in the given order, each in backticks: "`A`", "`A` and `B`", or "`A`, `B`, and `C`".
	private static func listed(_ moduleNames: [String]) -> String {
		let spelledNames = moduleNames.map { "`\($0)`" }
		return if spelledNames.count <= 2 {
			spelledNames.joined(separator: " and ")
		} else {
			"\(spelledNames.dropLast().joined(separator: ", ")), and \(spelledNames[spelledNames.count - 1])"
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
