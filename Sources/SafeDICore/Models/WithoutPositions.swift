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

// A module info file carries, beside its module's own declarations, the declarations of other modules that a seam or
// public mock of a module it depends on is computed from. Those carry no line or column: a position is what an edit
// elsewhere in a file changes, and nothing a signature reads, so a module whose `.safedi` holds them is rebuilt only
// when a declaration a signature can depend on changes. Every fact stays: which file holds a declaration
// (`sourceFilePath`), and whether a declaration spells an access modifier (`AccessDeclaration.spellsAccessModifier`).

extension Instantiable {
	/// This declaration without a line or column anywhere in it: every `Dependency.DeclarationLocation` and
	/// `Dependency.SourceRange` it holds is `nil`.
	public func withoutPositions() -> Instantiable {
		var instantiable = Instantiable(
			instantiableType: concreteInstantiable,
			isRoot: isRoot,
			generatesDependencyTree: generatesDependencyTree,
			initializer: initializer?.withoutPositions(),
			otherInitializers: otherInitializers.map { $0.withoutPositions() },
			additionalInstantiables: Array(instantiableTypes.dropFirst()),
			dependencies: dependencies.map { $0.withoutPositions() },
			declarationType: declarationType,
			access: access.withoutPositions(),
			enclosingTypeAccess: enclosingTypeAccess.map { $0.withoutPositions() },
			enclosingExtensionAccess: enclosingExtensionAccess?.withoutPositions(),
			generatedInitializerAttributes: generatedInitializerAttributes,
			mockAttributes: mockAttributes,
			declarationIsolation: declarationIsolation,
			generateMock: generateMock,
			mockGenerationArgumentRange: nil,
			mockOnly: mockOnly,
			mockInitializer: mockInitializer?.withoutPositions(),
			mockReturnType: mockReturnType,
			customMockName: customMockName,
			mockDeclarationLocation: nil,
			mockDeclarationAccess: mockDeclarationAccess?.withoutPositions(),
			mockDeclarationModuleName: mockDeclarationModuleName,
			mockDeclarationPackageName: mockDeclarationPackageName,
			declarationLocation: nil,
			moduleName: moduleName,
			packageName: packageName,
		)
		instantiable.sourceFilePath = sourceFilePath
		instantiable.dependencyLabelsInUnselectedClauses = dependencyLabelsInUnselectedClauses.map {
			DependencyLabelInUnselectedClause(label: $0.label, clause: $0.clause, clauseLocation: nil, isDeclaredDirectlyInClause: $0.isDeclaredDirectlyInClause)
		}
		instantiable.dependencyLabelsInsideConditionalBlocks = dependencyLabelsInsideConditionalBlocks
		return instantiable
	}
}

extension Dependency {
	/// This dependency without where it is declared.
	public func withoutPositions() -> Dependency {
		Dependency(property: property, source: source)
	}
}

extension Initializer {
	/// This initializer without where its access modifier is.
	public func withoutPositions() -> Initializer {
		Initializer(
			access: access.withoutPositions(),
			isOptional: isOptional,
			isAsync: isAsync,
			doesThrow: doesThrow,
			hasGenericParameter: hasGenericParameter,
			hasGenericWhereClause: hasGenericWhereClause,
			arguments: arguments,
			spelledIsolation: spelledIsolation,
		)
	}
}

extension AccessDeclaration {
	/// This access without where its modifier and its declaration are, keeping whether a modifier is spelled.
	public func withoutPositions() -> AccessDeclaration {
		AccessDeclaration(level: level, spellsAccessModifier: spellsAccessModifier, isExtension: isExtension)
	}
}

extension PlainTypeDeclaration {
	/// This declaration without where its access modifiers and its declaration are.
	public func withoutPositions() -> PlainTypeDeclaration {
		PlainTypeDeclaration(
			typeDescription: typeDescription,
			access: access.withoutPositions(),
			enclosingTypeAccess: enclosingTypeAccess.map { $0.withoutPositions() },
			enclosingExtensionAccess: enclosingExtensionAccess?.withoutPositions(),
			moduleName: moduleName,
			packageName: packageName,
			sourceFilePath: sourceFilePath,
		)
	}
}

extension StoredSeamSignature {
	/// This signature without a line or column anywhere in it, as a module info file's view carries it: a declaration
	/// another module records is read without positions, and a signature computed from such declarations has none.
	public func withoutPositions() -> StoredSeamSignature {
		StoredSeamSignature(seamType: seamType, signature: signature?.withoutPositions())
	}
}

extension SeamSignature {
	func withoutPositions() -> SeamSignature {
		SeamSignature(
			seamType: seamType,
			parameters: parameters.map { $0.withoutPositions() },
			tiers: tiers,
			noTierParameters: noTierParameters.map { $0.withoutPositions() },
			holes: holes.map { $0.withoutPositions() },
			builders: builders.map { $0.withoutPositions() },
			scopeEnums: scopeEnums.map { $0.withoutPositions() },
			callRoutes: callRoutes.map { $0.withoutPositions() },
			typesDeclaredEscaping: typesDeclaredEscaping,
		)
	}
}

extension SeamSignature.Receiver {
	func withoutPositions() -> SeamSignature.Receiver {
		SeamSignature.Receiver(property: property, declaringType: declaringType, declarationLocation: nil, access: access, aliasProperty: aliasProperty, isInstantiateMethodParameter: isInstantiateMethodParameter)
	}
}

extension SeamSignature.Parameter {
	func withoutPositions() -> SeamSignature.Parameter {
		SeamSignature.Parameter(
			storing: property,
			isPassThrough: isPassThrough,
			access: access,
			accessCause: accessCause?.withoutPositions(),
			tierAccess: tierAccess,
			isOnlyIfAvailable: isOnlyIfAvailable,
			requiredThroughAlias: requiredThroughAlias,
			receivers: receivers.map { $0.withoutPositions() },
			nestedSeamCall: nestedSeamCall,
			deferral: deferral,
			internalName: internalName,
			otherInitializerArgumentsAccess: otherInitializerArgumentsAccess,
		)
	}
}

extension SeamSignature.Hole {
	func withoutPositions() -> SeamSignature.Hole {
		SeamSignature.Hole(
			storing: ownerType,
			declaringModuleNames: declaringModuleNames,
			property: property,
			instantiatedType: instantiatedType,
			declarationLocation: nil,
			erasedToConcreteExistential: erasedToConcreteExistential,
			sitePath: sitePath,
			declaredSitePath: declaredSitePath.map { $0.withoutPositions() },
			fillPropertyStack: fillPropertyStack,
			fillConcreteTypeStack: fillConcreteTypeStack,
			builderLabel: builderLabel,
			narrowerTierBuilderLabels: narrowerTierBuilderLabels,
			internalName: internalName,
			scopeSeamType: scopeSeamType,
			scopeSeamModule: scopeSeamModule,
			typesToOwner: typesToOwner,
			scopeTypeName: scopeTypeName,
			enumPlace: enumPlace?.withoutPositions(),
			wrapperFunctionName: wrapperFunctionName,
			fields: fields.map { $0.withoutPositions() },
			tierAccess: tierAccess,
			accessCause: accessCause?.withoutPositions(),
			uncarriedDeclarations: uncarriedDeclarations.map { $0.withoutPositions() },
			cycleReentryDeclarations: cycleReentryDeclarations.map { $0.withoutPositions() },
			reenteringCallDeclarations: reenteringCallDeclarations.map { $0.withoutPositions() },
			reenteringPlaceFields: reenteringPlaceFields.map { $0.withoutPositions() },
			declarationsHiddenByFields: declarationsHiddenByFields.map { $0.withoutPositions() },
			innerSeamType: innerSeamType,
			passedUpRoute: passedUpRoute.map { $0.withoutPositions() },
			isSendable: isSendable,
		)
	}
}

extension SeamSignature.Hole.Field {
	func withoutPositions() -> SeamSignature.Hole.Field {
		SeamSignature.Hole.Field(
			property: property,
			access: access,
			accessCause: accessCause?.withoutPositions(),
			declaringType: declaringType,
			declarationLocation: nil,
			isReceivedOnlyIfAvailable: isReceivedOnlyIfAvailable,
			parameterTakingType: parameterTakingType,
			deferral: deferral,
			bindsMemo: bindsMemo,
			isSeamParameter: isSeamParameter,
			isBoundByPublicMockRoot: isBoundByPublicMockRoot,
			seamParameterOrigin: seamParameterOrigin.map {
				SeamSignature.Hole.Field.SeamParameterOrigin(seamType: $0.seamType, seamDeclarationLocation: nil, isPassThrough: $0.isPassThrough, receivers: $0.receivers.map { $0.withoutPositions() })
			},
		)
	}
}

extension SeamSignature.Hole.UncarriedDeclaration {
	func withoutPositions() -> SeamSignature.Hole.UncarriedDeclaration {
		let reason: Reason = if case let .boundOutsideSendableFunction(functionProperty, function, isForwarded, cycleParameter, alias) = reason {
			.boundOutsideSendableFunction(
				functionProperty: functionProperty,
				function: function,
				isForwarded: isForwarded,
				cycleParameter: cycleParameter.map { CycleParameterOrigin(takingType: $0.takingType, property: $0.property, declaringType: $0.declaringType, declarationLocation: nil, isForwarded: $0.isForwarded) },
				alias: alias,
			)
		} else {
			self.reason
		}
		return SeamSignature.Hole.UncarriedDeclaration(
			storing: property,
			declaringType: declaringType,
			declarationLocation: nil,
			parameterTakingType: parameterTakingType,
			builtAfter: builtAfter,
			reason: reason,
			isBoundFromCallersArgument: isBoundFromCallersArgument,
			isBuildableAboveSeam: isBuildableAboveSeam,
			labelsHeldAboveSeam: labelsHeldAboveSeam,
			placesInTree: placesInTree,
			holdsPlaceFilledElsewhere: holdsPlaceFilledElsewhere,
		)
	}
}

extension SeamSignature.Hole.CycleReentryDeclaration {
	func withoutPositions() -> SeamSignature.Hole.CycleReentryDeclaration {
		SeamSignature.Hole.CycleReentryDeclaration(property: property, declaringType: declaringType, declarationLocation: nil, parameterTakingType: parameterTakingType, closedOnProperty: closedOnProperty, closedOnBuiltType: closedOnBuiltType, closedOnDeclaringType: closedOnDeclaringType, reenteringType: reenteringType)
	}
}

extension SeamSignature.Hole.ReenteringCallDeclaration {
	func withoutPositions() -> SeamSignature.Hole.ReenteringCallDeclaration {
		SeamSignature.Hole.ReenteringCallDeclaration(property: property, declaringType: declaringType, declarationLocation: nil, pathPlace: pathPlace, callingType: callingType, callProperty: callProperty, calledSeam: calledSeam, reenteredPlace: reenteredPlace, reenteredSeamModule: reenteredSeamModule, fillingModule: fillingModule)
	}
}

extension SeamSignature.Hole.ReenteringPlaceField {
	func withoutPositions() -> SeamSignature.Hole.ReenteringPlaceField {
		SeamSignature.Hole.ReenteringPlaceField(
			carried: SeamSignature.Hole.FieldOfReenteringPlace(field: carried.field.withoutPositions(), reenteringPlace: carried.reenteringPlace, callProperty: carried.callProperty, calledSeam: carried.calledSeam),
			reenteredPlace: reenteredPlace,
			reenteredSeamModule: reenteredSeamModule,
			fillingModule: fillingModule,
		)
	}
}

extension SeamSignature.Hole.DeclarationHiddenByField {
	func withoutPositions() -> SeamSignature.Hole.DeclarationHiddenByField {
		SeamSignature.Hole.DeclarationHiddenByField(property: property, declaringType: declaringType, declarationLocation: nil, calledSeam: calledSeam, receivingSeam: receivingSeam)
	}
}

extension SeamSignature.Hole.DeclaredProperty {
	func withoutPositions() -> SeamSignature.Hole.DeclaredProperty {
		SeamSignature.Hole.DeclaredProperty(property: property, declaringType: declaringType, declarationLocation: nil)
	}
}

extension SeamSignature.Hole.EnumPlace {
	func withoutPositions() -> SeamSignature.Hole.EnumPlace {
		SeamSignature.Hole.EnumPlace(
			nestedByTypeIn: enumTypeName,
			rootEnumTypeName: rootEnumTypeName,
			caseName: caseName,
			valuesTypeName: valuesTypeName,
			memberValuesTypeName: memberValuesTypeName,
			isBuiltBySendableBuilder: isBuiltBySendableBuilder,
			route: route.map { $0.withoutPositions() },
			values: values.map { $0.withoutPositions() },
		)
	}
}

extension SeamSignature.Hole.RouteStep {
	func withoutPositions() -> SeamSignature.Hole.RouteStep {
		SeamSignature.Hole.RouteStep(
			caseName: caseName,
			values: values.map { Values(bindingName: $0.bindingName, type: $0.type, fields: $0.fields.map { $0.withoutPositions() }, bindingPath: $0.bindingPath) },
			innerScope: innerScope,
			leadsIntoFill: leadsIntoFill,
			member: member.map { Member(bindingName: $0.bindingName, valuesType: $0.valuesType, fields: $0.fields.map { $0.withoutPositions() }, levelType: $0.levelType, bindingPath: $0.bindingPath, isCalledInsideFunction: $0.isCalledInsideFunction) },
		)
	}
}

extension SeamSignature.CallRoute {
	func withoutPositions() -> SeamSignature.CallRoute {
		SeamSignature.CallRoute(sitePath: sitePath, innerKey: innerKey, rootKey: rootKey, route: route.map { $0.withoutPositions() }, caseName: caseName, memberValuesType: memberValuesType, handsFillLevelStruct: handsFillLevelStruct, reentersEnclosingFill: reentersEnclosingFill)
	}
}

extension SeamSignature.ScopeEnum {
	func withoutPositions() -> SeamSignature.ScopeEnum {
		SeamSignature.ScopeEnum(
			key: key,
			typeName: typeName,
			rootTypeName: rootTypeName,
			builderLabel: builderLabel,
			cases: cases.map { enumCase in
				Case(storing: enumCase.name, kind: enumCase.kind, values: enumCase.values.map { Values(typeName: $0.typeName, fields: $0.fields.map { $0.withoutPositions() }, labelsBoundLater: $0.labelsBoundLater) }, memberValuesTypeName: enumCase.memberValuesTypeName)
			},
		)
	}
}

extension SeamSignature.Builder {
	func withoutPositions() -> SeamSignature.Builder {
		SeamSignature.Builder(enumKey: enumKey, label: label, internalName: internalName, parameterType: parameterType, readableParameterType: readableParameterType, takesBuilderStruct: takesBuilderStruct, tierAccess: tierAccess, accessCause: accessCause?.withoutPositions(), narrowingInnerSeam: narrowingInnerSeam, narrowerTierLabels: narrowerTierLabels)
	}
}

extension TypeAccessProof.Cause {
	func withoutPositions() -> TypeAccessProof.Cause {
		switch self {
		case .ownDeclaration, .unproven:
			self
		case let .plainDeclaration(type, level, declarations, namesModules):
			.plainDeclaration(type: type, level: level, declarations: declarations.map { $0.withoutPositions() }, namesModules: namesModules)
		case let .declarationInExtensionOfRecordedType(type, ownLevel, extendedType, extendedTypeLevel, spellsOwnLevel, extendedTypeIsPlain, extendedTypeDeclarations, extendedTypeEnclosingType):
			.declarationInExtensionOfRecordedType(type: type, ownLevel: ownLevel, extendedType: extendedType, extendedTypeLevel: extendedTypeLevel, spellsOwnLevel: spellsOwnLevel, extendedTypeIsPlain: extendedTypeIsPlain, extendedTypeDeclarations: extendedTypeDeclarations.map { $0.withoutPositions() }, extendedTypeEnclosingType: extendedTypeEnclosingType)
		case let .declarationInExtension(type, level, extendedType, extensionLevel, isExtensionBased, enclosingTypeLevel, raisingProvers, isMockOnly):
			.declarationInExtension(type: type, level: level, extendedType: extendedType, extensionLevel: extensionLevel, isExtensionBased: isExtensionBased, enclosingTypeLevel: enclosingTypeLevel, raisingProvers: raisingProvers.map { $0.withoutPositions() }, isMockOnly: isMockOnly)
		case let .signatures(type, level, provers, mentioningModuleName):
			.signatures(type: type, level: level, provers: provers.map { $0.withoutPositions() }, mentioningModuleName: mentioningModuleName)
		case let .enclosedBy(type, enclosingType, cause):
			.enclosedBy(type: type, enclosingType: enclosingType, cause: cause.withoutPositions())
		}
	}
}

extension TypeAccessProof.Prover {
	func withoutPositions() -> TypeAccessProof.Prover {
		TypeAccessProof.Prover(carrier: carrier, member: member, argumentLabels: argumentLabels, level: level, location: nil, cap: cap?.withoutPositions())
	}
}
