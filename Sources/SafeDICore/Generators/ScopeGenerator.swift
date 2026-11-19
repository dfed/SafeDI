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
import SwiftParser
import SwiftSyntax

/// A model capable of generating code for a scope’s dependency tree.
actor ScopeGenerator: CustomStringConvertible, Sendable {
	// MARK: Initialization

	/// - Parameters:
	///   - propertiesToDeclare: The properties the scope declares for the scopes it builds, which its children therefore
	///     do not receive from its ancestors (see `Scope.propertiesToDeclare`). Empty for a scope that closes a property
	///     cycle, which builds nothing.
	///   - instantiatedDependenciesNotGenerated: The `@Instantiated` dependencies of the scope's type that a mock is passed
	///     because no scope builds them (see `Scope.instantiatedDependenciesNotGenerated`). Empty for a scope that closes a
	///     property cycle, which builds nothing.
	///   - closedOnDeclaration: For a scope that closes a property cycle, the declaration it repeats (see
	///     `closedOnDeclaration`).
	///   - receivesPassedNil: The properties the type's dependencies receive only if available that a mock passes `nil`
	///     though its root binds a form they read, as production always passes them `nil` (see
	///     `NearestDeclarations.binding(_:passingNilTo:)`): among `unavailableOptionalProperties`, and received from no
	///     scope above, so that the mock root binds and offers nothing that only they would read.
	///   - enclosingLevelCalls: For a call of another module's public mock, each level function an enclosing call declares
	///     that a case of this call's level functions re-enters, and the values the case hands it, by its dispatcher's key
	///     (`PublicMockLevelFunctions.init`).
	init(
		instantiable: Instantiable,
		property: Property?,
		propertiesToGenerate: [ScopeGenerator],
		propertiesToDeclare: Set<Property>,
		instantiatedDependenciesNotGenerated: [Dependency],
		unavailableOptionalProperties: Set<Property>,
		receivesPassedNil: Set<Property> = [],
		lazilyInstantiatedInstanceProperties: Set<Property>,
		forwardedLazilyInstantiatedInstanceProperties: [Property],
		erasedToConcreteExistential: Bool,
		isPropertyCycle: Bool,
		closedOnDeclaration: BuiltDeclaration? = nil,
		closedOnFillPathDeclarationsBeneath: Int? = nil,
		builtInlineSeamComment: String?,
		seamCall: SeamCall? = nil,
		publicMockCall: PublicMockCall? = nil,
		seamRoot: SeamRoot? = nil,
		mockBuilders: DependencyTreeGenerator.ShapedBuilders? = nil,
		holeCallArguments: [HoleCallArgument] = [],
		builderCallArguments: [BuilderCallArgument] = [],
		fillDispatchers: [FillDispatcher] = [],
		namesTakenByCall: Set<String> = [],
		passedUpHoles: [SeamSignature.Hole] = [],
		valuesBindings: [SeamHoles.ValuesBinding] = [],
		holdsLoopPayloadsInBoxes: Bool = false,
		memberCallsInsideFunction: [SeamHoles.ValuesBinding] = [],
		sendableFunctionsAreNonisolated: Bool = false,
		isBuiltByFill: Bool = false,
		fillReturnsWrapperBuilder: Bool = false,
		innerScopesCalledWithForwardedValue: [String] = [],
		fill: (hole: SeamSignature.Hole, key: String, functionName: String, boundLabels: Set<String>, fields: [SeamSignature.Hole.Field], caseHoles: [SeamSignature.Hole], emitsCode: Bool, callerReads: FillCallerReads, labelsHandedAsMemo: Set<String>, plainMemoRoutesOfSendableWrapperReads: [String: [FillDispatcher.PlainMemoRoute]], memoOriginsByLabel: [String: [SeamSignature.Hole.Field.SeamParameterOrigin]])? = nil,
		constructsWithHandWrittenMock: Bool = false,
		cycleParameters: [CycleParameter] = [],
		builtCycleParameters: [CycleParameter] = [],
		cycleParameterUnavailableProperties: Set<Property> = [],
		callSiteLazilyInstantiatedInstanceProperties: Set<Property>? = nil,
		reboundProperties: Set<Property> = [],
		previousPassReceivedBuilderLoops: ReceivedBuilderLoops? = nil,
		previousPassFillSendableWrapperReads: [String: [String: Property]] = [:],
		previousPassFillLabelsReadOnlyAsPlaceField: [String: Set<String>] = [:],
		previousPassPublicMockLevelReentries: [String: PublicMockLevelFunctions.Reentry] = [:],
		enclosingLevelCalls: [String: PublicMockLevelFunctions.EnclosingLevelCall] = [:],
		namesBoundBySeam: Set<String> = [],
		placeHoldingProperties: Set<Property>? = nil,
	) {
		self.placeHoldingProperties = placeHoldingProperties
		self.builtInlineSeamComment = builtInlineSeamComment
		self.namesBoundBySeam = namesBoundBySeam
		self.constructsWithHandWrittenMock = constructsWithHandWrittenMock
		self.closedOnDeclaration = closedOnDeclaration
		self.closedOnFillPathDeclarationsBeneath = closedOnFillPathDeclarationsBeneath
		self.cycleParameters = cycleParameters
		self.cycleParameterUnavailableProperties = cycleParameterUnavailableProperties
		self.callSiteLazilyInstantiatedInstanceProperties = callSiteLazilyInstantiatedInstanceProperties ?? lazilyInstantiatedInstanceProperties
		self.publicMockCall = publicMockCall
		self.mockBuilders = mockBuilders
		self.holeCallArguments = holeCallArguments
		self.builderCallArguments = builderCallArguments
		self.fillDispatchers = fillDispatchers
		fillKey = fill?.key
		fillStructBoundLabels = fill?.boundLabels ?? []
		fillBindsDeferredFieldsFromStruct = fill.map { fill in fill.hole.innerSeamType != nil && fill.fields.contains { $0.isDeferredParameter && fill.boundLabels.contains($0.property.label) } } ?? false
		fillLabelsHandedAsMemo = fill?.labelsHandedAsMemo ?? []
		fillPlainMemoRoutesOfSendableWrapperReads = fill?.plainMemoRoutesOfSendableWrapperReads ?? [:]
		fillMemoOriginsByLabel = fill?.memoOriginsByLabel ?? [:]
		fillFields = fill?.fields ?? []
		fillCaseHoles = fill?.caseHoles ?? []
		fillEmitsCode = fill?.emitsCode ?? true
		fillCallerReads = fill?.callerReads ?? FillCallerReads()
		ownerPropertyStack = []
		ownerConcreteTypeStack = []
		self.passedUpHoles = passedUpHoles
		self.valuesBindings = valuesBindings
		self.memberCallsInsideFunction = memberCallsInsideFunction
		self.sendableFunctionsAreNonisolated = sendableFunctionsAreNonisolated
		self.isBuiltByFill = isBuiltByFill
		self.fillReturnsWrapperBuilder = fillReturnsWrapperBuilder
		self.innerScopesCalledWithForwardedValue = innerScopesCalledWithForwardedValue
		if let fill {
			scopeData = .fill(hole: fill.hole, functionName: fill.functionName)
			description = fill.hole.builderLabel
		} else if let property {
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
				seamCall: seamCall,
			)
			description = instantiable.concreteInstantiable.asSource
		} else {
			scopeData = .root(instantiable: instantiable, seamRoot: seamRoot)
			description = instantiable.concreteInstantiable.asSource
		}
		self.property = property
		let declaration = property.map { BuiltDeclaration(property: $0, concreteType: instantiable.concreteInstantiable) }
		self.declaration = declaration
		self.propertiesToGenerate = propertiesToGenerate
		// What the code generated for the call's dispatchers decides, from the fills its children generate.
		if publicMockCall != nil, !fillDispatchers.isEmpty {
			var fillParametersByKey = [String: [SeamSignature.Hole.Field]]()
			var fillNames = Set<String>()
			// What the root level functions read of the caller's scope, as a seam's root dispatcher reads it: each label in the
			// form `FillDispatcher.dispatcherParameters(of:fillReads:)` types a dispatcher's parameter by, the form no fill
			// reads optionally first, then in `Property` order, so neither the order of the fills nor of their cases decides it,
			// handed as a fill that takes that form reads it: the caller's declaration in one form is the same for every fill of
			// the call, which each read of the one scope enclosing the call (`Scope.Fill.callerNearestDeclarations`).
			var callerReadFormsByLabel = [String: [Property: (field: SeamSignature.Hole.Field, argument: String)]]()
			for child in propertiesToGenerate {
				if let key = child.fillKey, child.fillEmitsCode {
					fillParametersByKey[key] = child.fillParameterFields
					for (label, argument) in child.fillCallerReads.argumentByLabel {
						guard let field = child.fillCallerReads.parameterByLabel[label] else { continue }
						callerReadFormsByLabel[label, default: [:]].merge([field.property: (field, argument)]) { form, _ in form }
					}
				}
				if case let .fill(_, functionName) = child.scopeData {
					fillNames.insert(functionName)
				}
			}
			var callerReads = [String: (field: SeamSignature.Hole.Field, argument: String)]()
			for (label, forms) in callerReadFormsByLabel {
				let properties = forms.keys.sorted()
				guard let property = properties.first(where: { !$0.typeDescription.isOptional }) ?? properties.first,
				      let form = forms[property]
				else { continue }
				callerReads[label] = form
			}
			publicMockLevelFunctions = PublicMockLevelFunctions(
				dispatchers: fillDispatchers,
				fillParametersByKey: fillParametersByKey,
				roots: builderCallArguments.compactMap { builderCallArgument in
					builderCallArgument.builderStruct.flatMap { builderStruct in
						builderStruct.rootDispatcherKey.map { PublicMockLevelFunctions.Root(label: builderCallArgument.label, dispatcherKey: $0, carriedStructs: builderStruct.carriedStructs) }
					}
				},
				reservedNames: namesTakenByCall.union(fillNames),
				callerReads: callerReads,
				enclosingLevelCalls: enclosingLevelCalls,
			)
		} else {
			publicMockLevelFunctions = nil
		}
		containsBuildSite = propertiesToGenerate.contains(where: \.containsBuildSite)
		if containsBuildSite {
			// A site's field of a label declared here reads this scope's declaration, or the site carries no field of it.
			let labelsDeclaredHere = if let fill {
				fill.boundLabels.union(fill.caseHoles.flatMap(\.uncarriedDeclarations).map(\.property.label))
			} else {
				Set(propertiesToGenerate.compactMap(\.property?.label) + instantiable.dependencies.filter { $0.source == .forwarded }.map(\.property.label))
			}
			fieldsCarriedBySites = Set(propertiesToGenerate.flatMap(\.fieldsCarriedBySites).filter { !labelsDeclaredHere.contains($0.label) })
		} else {
			fieldsCarriedBySites = []
		}
		passesUpBuilder = !passedUpHoles.isEmpty || propertiesToGenerate.contains(where: \.passesUpBuilder)
		holdsCallReenteringEnclosingFill = holeCallArguments.contains { $0.enclosingFillKey != nil } || propertiesToGenerate.contains(where: \.holdsCallReenteringEnclosingFill)
		typesDeclaredEscaping = Self.typesDeclaredEscaping(
			instantiable: instantiable,
			publicMockCall: publicMockCall,
			seamCall: seamCall,
			children: propertiesToGenerate,
		)
		declaresBuilderFunction = property != nil && !isPropertyCycle
		let cycleClosings = Self.cycleClosings(
			children: propertiesToGenerate,
			property: property,
			declaration: declaration,
			closedOnDeclaration: closedOnDeclaration,
			isPropertyCycle: isPropertyCycle,
		)
		childrenTakePartInCycle = cycleClosings.childrenTakePartInCycle
		cycleClosedOnDeclarations = cycleClosings.cycleClosedOnDeclarations
		isReferencedByCycleClosingScope = cycleClosings.isReferencedByCycleClosingScope
		buildsInSendableFunction = cycleClosings.buildsInSendableFunction
		cycleClosedOnDeclarationsReferencedFromSendableFunction = cycleClosings.cycleClosedOnDeclarationsReferencedFromSendableFunction
		let fillReferences = Self.fillReferences(
			holeCallArguments: holeCallArguments,
			builderCallArguments: builderCallArguments,
			fillDispatchers: fillDispatchers,
			publicMockLevelFunctions: publicMockLevelFunctions,
			children: propertiesToGenerate,
			buildsInSendableFunction: cycleClosings.buildsInSendableFunction,
		)
		sendableFillKeys = fillReferences.sendableFillKeys
		namedFillKeys = fillReferences.namedFillKeys
		inlinableFillKeys = fillReferences.inlinableFillKeys
		referencedFillNamesByKey = fillReferences.referencedFillNamesByKey
		fillKeysReferencedFromSendableFunction = fillReferences.fillKeysReferencedFromSendableFunction
		publicMockLevelReentries = fillReferences.publicMockLevelReentries
		publicMockLevelReentriesChangedInTree = fillReferences.publicMockLevelReentries != previousPassPublicMockLevelReentries
			|| propertiesToGenerate.contains(where: \.publicMockLevelReentriesChangedInTree)
		let deferredFillLabels = Self.deferredFillLabels(
			children: propertiesToGenerate,
			previousPassFillSendableWrapperReads: previousPassFillSendableWrapperReads,
			previousPassFillLabelsReadOnlyAsPlaceField: previousPassFillLabelsReadOnlyAsPlaceField,
		)
		fillDeferredLabelsHiddenByReenteringCalls = deferredFillLabels.hiddenByReenteringCalls
		fillDeferredLabelsReadInsideSendableFunction = deferredFillLabels.readInsideSendableFunction
		fillSendableWrapperReads = deferredFillLabels.sendableWrapperReads
		fillLabelsReadOnlyAsPlaceField = deferredFillLabels.readOnlyAsPlaceField
		fillStructBoundLabelsChangedInTree = deferredFillLabels.fillStructBoundLabelsChangedInTree
		self.propertiesToDeclare = propertiesToDeclare
		self.instantiatedDependenciesNotGenerated = instantiatedDependenciesNotGenerated
		self.unavailableOptionalProperties = unavailableOptionalProperties
		self.lazilyInstantiatedInstanceProperties = lazilyInstantiatedInstanceProperties
		fulfillingPropertyIsLazilyInstantiatedInstance = false
		fulfillingBindingIsOptional = false
		fulfillingExpression = nil
		declaredLazilyInstantiatedInstanceProperty = property?.asLazilyInstantiatedInstanceProperty
		onlyIfAvailableDependencies = Self.onlyIfAvailableDependencies(of: instantiable.dependencies, cycleParameters: cycleParameters)
		// A forwarded lazily instantiated property is also received by value, as the instance it creates.
		let forwardedProperties = if forwardedLazilyInstantiatedInstanceProperties.isEmpty {
			scopeData.forwardedProperties
		} else {
			scopeData.forwardedProperties.union(forwardedLazilyInstantiatedInstanceProperties)
		}
		// A scope that closes a cycle builds nothing, but the builder function it calls declares what its type instantiates
		// and forwards, so an alias of one of those is bound inside that function, which binds its own: the scope receives
		// nothing for it.
		let aliasBindingDeclaredProperties = isPropertyCycle ? Self.propertiesDeclared(byOwnDependencies: instantiable.dependencies) : propertiesToDeclare
		let receives = Self.receives(
			children: propertiesToGenerate,
			ownDependencies: instantiable.dependencies,
			receivesPassedNil: receivesPassedNil,
			propertiesToDeclare: propertiesToDeclare,
			forwardedProperties: forwardedProperties,
			aliasBindingDeclaredProperties: aliasBindingDeclaredProperties,
			cycleParameters: isPropertyCycle ? cycleParameters : [],
		)
		receivedProperties = receives.receivedProperties
		requiredReceivedProperties = receives.requiredReceivedProperties
		let publicMockCallReceives = Self.publicMockCallReceives(
			children: propertiesToGenerate,
			ownDependencies: instantiable.dependencies,
			publicMockCall: publicMockCall,
			ownReceivedProperties: receives.ownReceivedProperties,
			propertiesToDeclare: propertiesToDeclare,
			forwardedProperties: forwardedProperties,
		)
		receivedOnlyByPublicMockCalls = publicMockCallReceives.receivedOnlyByPublicMockCalls
		passedByPublicMockCalls = publicMockCallReceives.passedByPublicMockCalls
		var unwrappedOptionalRequiredReceivedProperties = Set<Property>()
		for property in receives.requiredReceivedProperties where property.typeDescription.isOptional {
			unwrappedOptionalRequiredReceivedProperties.insert(property.asUnwrappedProperty)
		}
		self.unwrappedOptionalRequiredReceivedProperties = unwrappedOptionalRequiredReceivedProperties
		let aliasRequirements = Self.aliasRequirements(
			children: propertiesToGenerate,
			propertiesToDeclare: propertiesToDeclare,
			forwardedProperties: forwardedProperties,
			cycleParameters: isPropertyCycle ? cycleParameters : [],
			seamCall: seamCall,
		)
		requiredOnlyIfAvailableAliasProperties = aliasRequirements.requiredOnlyIfAvailableAliasProperties
		requiredAliasFulfillingProperties = aliasRequirements.requiredAliasFulfillingProperties
		onlyIfAvailableAliasFulfillingProperty = nil
		onlyIfAvailableUnwrappedReceivedProperties = Self.onlyIfAvailableUnwrappedReceivedProperties(
			children: propertiesToGenerate,
			ownDependencies: instantiable.dependencies,
			receivesPassedNil: receivesPassedNil,
			propertiesToDeclare: propertiesToDeclare,
			forwardedProperties: forwardedProperties,
			aliasBindingDeclaredProperties: aliasBindingDeclaredProperties,
			cycleParameters: isPropertyCycle ? cycleParameters : [],
			requiredReceivedProperties: receives.requiredReceivedProperties,
		)
		let cycleParameterSearch = Self.cycleParameterSearch(
			instantiable: instantiable,
			property: property,
			declaration: declaration,
			closedOnDeclaration: closedOnDeclaration,
			isPropertyCycle: isPropertyCycle,
			childrenTakePartInCycle: cycleClosings.childrenTakePartInCycle,
			children: propertiesToGenerate,
			propertiesToDeclare: propertiesToDeclare,
			forwardedProperties: forwardedProperties,
			cycleParameters: cycleParameters,
			receivedProperties: receives.receivedProperties,
			requiredReceivedProperties: receives.requiredReceivedProperties,
			requiredAliasFulfillingProperties: aliasRequirements.requiredAliasFulfillingProperties,
			onlyIfAvailableUnwrappedReceivedProperties: onlyIfAvailableUnwrappedReceivedProperties,
		)
		cycleClosingRedeclaredLabels = cycleParameterSearch.cycleClosingRedeclaredLabels
		foundCycleParameters = cycleParameterSearch.foundCycleParameters
		unpassableCycleLabelsInTree = cycleParameterSearch.unpassableCycleLabelsInTree
		cycleParametersChangedInTree = cycleParameterSearch.foundCycleParameters != builtCycleParameters
			|| propertiesToGenerate.contains(where: \.cycleParametersChangedInTree)
		// A scope that closes a cycle builds nothing, so its children are on no loop. A fill's one child is the property it
		// fills, whose builder function the seam's initializer declares: a receive of that property in the fill's tree is a
		// fill finding (`receivesInstantiatorBuildingSite`), never a loop the fill rebinds.
		let receivedBuilderLoops = isPropertyCycle || fill != nil
			? ReceivedBuilderLoops()
			: Self.receivedBuilderLoops(of: propertiesToGenerate, requiredOnlyIfAvailableAliasProperties: aliasRequirements.requiredOnlyIfAvailableAliasProperties)
		self.receivedBuilderLoops = receivedBuilderLoops
		receivedBuilderLoopsChangedInTree = receivedBuilderLoops != (previousPassReceivedBuilderLoops ?? ReceivedBuilderLoops())
			|| propertiesToGenerate.contains(where: \.receivedBuilderLoopsChangedInTree)
		// In a seam's own tree, a loop whose members bind two or more payloads or levels holds them in one box, unless a
		// member's function is `@Sendable`, which could not capture the box (see `boxedLoops`).
		var boxedLoops = [Int: String]()
		var loopLevelsTypesInTree = [String: String]()
		if holdsLoopPayloadsInBoxes, !receivedBuilderLoops.loopByChildIndex.isEmpty {
			// Each loop's bindings in index order, the order the body generates its members in (`orderedPropertiesToGenerate`).
			var bindingsByLoop = [Int: [SeamHoles.ValuesBinding]]()
			for (index, loop) in receivedBuilderLoops.loopByChildIndex.sorted(by: { $0.key < $1.key }) where !propertiesToGenerate[index].isAlias {
				bindingsByLoop[loop, default: []] += propertiesToGenerate[index].valuesBindings
			}
			let loopsWithSendableFunction = Set(receivedBuilderLoops.loopByChildIndex.filter { propertiesToGenerate[$0.key].buildsInSendableFunction }.values)
			for (loop, bindings) in bindingsByLoop where bindings.count > 1 && !loopsWithSendableFunction.contains(loop) {
				let loopLevelsType = LoopLevelsType(holding: bindings)
				boxedLoops[loop] = loopLevelsType.name
				loopLevelsTypesInTree[loopLevelsType.name] = loopLevelsType.declaration
			}
		}
		for child in propertiesToGenerate where !child.loopLevelsTypesInTree.isEmpty {
			loopLevelsTypesInTree.merge(child.loopLevelsTypesInTree) { declaration, _ in declaration }
		}
		self.boxedLoops = boxedLoops
		self.loopLevelsTypesInTree = loopLevelsTypesInTree
		self.reboundProperties = if let property, let declaration, !isPropertyCycle, !reboundProperties.isEmpty {
			Self.reboundProperties(
				reboundProperties,
				builtProperty: property,
				builtDeclaration: declaration,
				instantiable: instantiable,
				children: propertiesToGenerate,
				forwardedProperties: forwardedProperties,
				cycleParameters: cycleParameters,
			)
		} else {
			[]
		}
	}

	// MARK: Initialization helpers

	// Each part of what the initializer works out from a scope's children is a function of its own, kept out of the
	// initializer: as one function, the initializer took most of the time an optimized build of this module takes.

	/// The names this scope's subtree declares `@escaping` (see `typesDeclaredEscaping`).
	@inline(never)
	nonisolated private static func typesDeclaredEscaping(
		instantiable: Instantiable,
		publicMockCall: PublicMockCall?,
		seamCall: SeamCall?,
		children: [ScopeGenerator],
	) -> Set<TypeDescription> {
		var typesDeclaredEscaping = Set(instantiable.initializer?.typesDeclaredEscaping ?? [])
		typesDeclaredEscaping.formUnion(instantiable.mockInitializer?.typesDeclaredEscaping ?? [])
		// An alias hands its receiver the value of the property it names, so a name that fulfills a property of a name
		// its initializers declare `@escaping` is a function type too, which a generated parameter of it must also spell
		// `@escaping`: `nameDeclaredEscaping` of that name spelled `@escaping`, which is `nil` for any type but a name. An
		// erased alias hands the value to an initializer instead, which may take any type.
		let initializerTypesDeclaredEscaping = typesDeclaredEscaping
		for dependency in instantiable.dependencies where initializerTypesDeclaredEscaping.contains(dependency.property.typeDescription) {
			if case let .aliased(fulfillingProperty: fulfillingProperty, erasedToConcreteExistential: false, onlyIfAvailable: _) = dependency.source,
			   let fulfillingName = TypeDescription.attributed(fulfillingProperty.typeDescription, specifiers: [], attributes: ["escaping"]).nameDeclaredEscaping
			{
				typesDeclaredEscaping.insert(fulfillingName)
			}
		}
		typesDeclaredEscaping.formUnion(publicMockCall?.typesDeclaredEscaping ?? [])
		typesDeclaredEscaping.formUnion(seamCall?.typesDeclaredEscaping ?? [])
		for child in children where !child.typesDeclaredEscaping.isEmpty {
			typesDeclaredEscaping.formUnion(child.typesDeclaredEscaping)
		}
		return typesDeclaredEscaping
	}

	/// What a scope's place in the cycles closed beneath it makes of it.
	private struct CycleClosings {
		let childrenTakePartInCycle: Bool
		let cycleClosedOnDeclarations: Set<BuiltDeclaration>
		let isReferencedByCycleClosingScope: Bool
		let buildsInSendableFunction: Bool
		let cycleClosedOnDeclarationsReferencedFromSendableFunction: Set<BuiltDeclaration>
	}

	@inline(never)
	nonisolated private static func cycleClosings(
		children: [ScopeGenerator],
		property: Property?,
		declaration: BuiltDeclaration?,
		closedOnDeclaration: BuiltDeclaration?,
		isPropertyCycle: Bool,
	) -> CycleClosings {
		// This runs at every scope of every tree, and nearly every child is outside every cycle.
		var childCycleClosedOnDeclarations = Set<BuiltDeclaration>()
		var childrenTakePartInCycle = false
		for child in children where child.isReferencedByCycleClosingScope || !child.cycleClosedOnDeclarations.isEmpty {
			childCycleClosedOnDeclarations.formUnion(child.cycleClosedOnDeclarations)
			childrenTakePartInCycle = true
		}
		let cycleClosedOnDeclarations: Set<BuiltDeclaration>
		let isReferencedByCycleClosingScope: Bool
		if let closedOnDeclaration {
			cycleClosedOnDeclarations = [closedOnDeclaration]
			isReferencedByCycleClosingScope = false
		} else if let declaration, childCycleClosedOnDeclarations.contains(declaration) {
			cycleClosedOnDeclarations = childCycleClosedOnDeclarations.subtracting([declaration])
			isReferencedByCycleClosingScope = true
		} else {
			cycleClosedOnDeclarations = childCycleClosedOnDeclarations
			isReferencedByCycleClosingScope = false
		}
		// A cycle-closing scope refers to the builder function of the enclosing scope it closes on. When a
		// `@Sendable` builder function lies between the two, it captures that function, which must then be
		// `@Sendable` too. So must it when the cycle-closing scope hands it to a `Sendable` wrapper of its own, which
		// takes a `@Sendable` function, whatever kind of declaration it repeats.
		var cycleClosedOnDeclarationsReferencedFromSendableFunction = Set<BuiltDeclaration>()
		for child in children {
			cycleClosedOnDeclarationsReferencedFromSendableFunction.formUnion(child.cycleClosedOnDeclarationsReferencedFromSendableFunction)
		}
		if let closedOnDeclaration, let property, property.propertyType.isSendable {
			cycleClosedOnDeclarationsReferencedFromSendableFunction.insert(closedOnDeclaration)
		}
		let buildsInSendableFunction = if let property, let declaration, !isPropertyCycle {
			property.propertyType.isSendable || cycleClosedOnDeclarationsReferencedFromSendableFunction.contains(declaration)
		} else {
			false
		}
		// A `@Sendable` builder function holds every reference its subtree makes to the builder functions
		// enclosing it, including those that made it `@Sendable`.
		if buildsInSendableFunction {
			cycleClosedOnDeclarationsReferencedFromSendableFunction.formUnion(childCycleClosedOnDeclarations)
		}
		if let declaration, !isPropertyCycle {
			cycleClosedOnDeclarationsReferencedFromSendableFunction.remove(declaration)
		}
		return CycleClosings(
			childrenTakePartInCycle: childrenTakePartInCycle,
			cycleClosedOnDeclarations: cycleClosedOnDeclarations,
			isReferencedByCycleClosingScope: isReferencedByCycleClosingScope,
			buildsInSendableFunction: buildsInSendableFunction,
			cycleClosedOnDeclarationsReferencedFromSendableFunction: cycleClosedOnDeclarationsReferencedFromSendableFunction,
		)
	}

	/// How the fills and dispatchers of a scope's calls are referred to, and which are `@Sendable` or inlined.
	private struct FillReferences {
		let sendableFillKeys: Set<String>
		let namedFillKeys: Set<String>
		let inlinableFillKeys: Set<String>
		let referencedFillNamesByKey: [String: String]
		let fillKeysReferencedFromSendableFunction: Set<String>
		let publicMockLevelReentries: [String: PublicMockLevelFunctions.Reentry]
	}

	@inline(never)
	nonisolated private static func fillReferences(
		holeCallArguments: [HoleCallArgument],
		builderCallArguments: [BuilderCallArgument],
		fillDispatchers: [FillDispatcher],
		publicMockLevelFunctions: PublicMockLevelFunctions?,
		children: [ScopeGenerator],
		buildsInSendableFunction: Bool,
	) -> FillReferences {
		// A call inside a fill of its seam's call refers to every fill of the enclosing call by name. Nearly no scope holds
		// such a call. Which of a call's own fills that makes `@Sendable` is decided here, where every function that can
		// refer to them has been built (see `sendableFills(of:referencedFromSendableFunctions:)`).
		var referencedFillNamesByKey = [String: String]()
		var fillKeysReferencedFromSendableFunction = Set<String>()
		for holeCallArgument in holeCallArguments {
			if let enclosingFillKey = holeCallArgument.enclosingFillKey {
				referencedFillNamesByKey[enclosingFillKey] = holeCallArgument.value
				if holeCallArgument.hole.isSendable {
					fillKeysReferencedFromSendableFunction.insert(enclosingFillKey)
				}
			}
		}
		// A dispatcher passed by name is referred to as a fill is, and is `@Sendable` where its argument is.
		for builderCallArgument in builderCallArguments {
			if let enclosingFill = builderCallArgument.enclosingFill {
				referencedFillNamesByKey[enclosingFill.key] = enclosingFill.name
				if builderCallArgument.isSendable {
					fillKeysReferencedFromSendableFunction.insert(enclosingFill.key)
				}
			}
		}
		for child in children where !child.referencedFillNamesByKey.isEmpty {
			referencedFillNamesByKey.merge(child.referencedFillNamesByKey) { name, _ in name }
			fillKeysReferencedFromSendableFunction.formUnion(child.fillKeysReferencedFromSendableFunction)
		}
		// A call inside a fill of this call that re-enters a level function hands it what it takes of the caller's scope, which
		// the pass before found (`Scope.enclosingLevelReentriesOfThisCall`). Nearly no call holds such a call.
		let publicMockLevelReentries = publicMockLevelFunctions?.levelReentries(amongKeys: Set(referencedFillNamesByKey.keys)) ?? [:]
		let ownFills = children.compactMap { child -> SendableFillNode? in
			child.fillKey.map { SendableFillNode(key: $0, references: Set(child.referencedFillNamesByKey.keys), startsSendable: child.fillHole?.isSendable == true) }
		} + fillDispatchers.map { dispatcher in
			SendableFillNode(key: dispatcher.key, references: Set(dispatcher.cases.compactMap(\.target?.key)), startsSendable: dispatcher.isSendableFamily)
		}
		// A call's own fills and dispatchers are declared in the function that makes it, which encloses every reference to them.
		let ownFillKeys = Set(ownFills.map(\.key))
		// A case of one of the call's dispatchers that leads to a dispatcher an enclosing call declares, which this call reuses
		// (`FillDispatcher.Case.Target.reusedCarriedInnerScopes`), refers to it by name, as a dispatcher passed by name is: a
		// `@Sendable` function between this call and the enclosing one makes it `@Sendable`.
		for target in fillDispatchers.flatMap({ $0.cases.compactMap(\.target) }) where !ownFillKeys.contains(target.key) {
			referencedFillNamesByKey[target.key] = target.name
		}
		if buildsInSendableFunction {
			fillKeysReferencedFromSendableFunction.formUnion(referencedFillNamesByKey.keys.filter { !ownFillKeys.contains($0) })
		}
		let sendableFills = Self.sendableFills(of: ownFills, referencedFromSendableFunctions: fillKeysReferencedFromSendableFunction)
		fillKeysReferencedFromSendableFunction.formUnion(sendableFills.referencedFillKeys)
		let namedFills = Self.namedFills(
			builderCallArguments: builderCallArguments,
			fillDispatchers: fillDispatchers,
			children: children,
			sendableFillKeys: sendableFills.keys,
		)
		return FillReferences(
			sendableFillKeys: sendableFills.keys,
			namedFillKeys: namedFills.namedFillKeys.subtracting(ownFillKeys),
			inlinableFillKeys: namedFills.inlinableFillKeys,
			referencedFillNamesByKey: referencedFillNamesByKey.filter { !ownFillKeys.contains($0.key) },
			fillKeysReferencedFromSendableFunction: fillKeysReferencedFromSendableFunction.subtracting(ownFillKeys),
			publicMockLevelReentries: publicMockLevelReentries,
		)
	}

	@inline(never)
	nonisolated private static func namedFills(
		builderCallArguments: [BuilderCallArgument],
		fillDispatchers: [FillDispatcher],
		children: [ScopeGenerator],
		sendableFillKeys: Set<String>,
	) -> (namedFillKeys: Set<String>, inlinableFillKeys: Set<String>) {
		// A fill that one case of one of the call's dispatchers calls, and nothing else refers to by name, is generated in
		// that case: one function fewer for each place, which is most of what a caller compiles. What refers to a fill by
		// name is a call's argument (an enclosing fill or dispatcher a call inside it passes) and a
		// dispatcher's case, the call's own or a call's inside one of its fills.
		var childNamedFillKeys = Set<String>()
		for child in children where !child.namedFillKeys.isEmpty {
			childNamedFillKeys.formUnion(child.namedFillKeys)
		}
		var namedFillKeys = childNamedFillKeys
		for enclosingFillKey in builderCallArguments.compactMap(\.enclosingFill?.key) {
			namedFillKeys.insert(enclosingFillKey)
		}
		var dispatcherCaseCountByTargetKey = [String: Int]()
		var dispatcherByTargetKey = [String: FillDispatcher]()
		for dispatcher in fillDispatchers {
			for target in dispatcher.cases.compactMap(\.target) {
				namedFillKeys.insert(target.key)
				dispatcherCaseCountByTargetKey[target.key, default: 0] += 1
				dispatcherByTargetKey[target.key] = dispatcher
			}
		}
		let inlinableFillKeys = Set(children.compactMap { child -> String? in
			guard let key = child.fillKey,
			      dispatcherCaseCountByTargetKey[key] == 1,
			      !childNamedFillKeys.contains(key),
			      let dispatcher = dispatcherByTargetKey[key],
			      // A dispatcher that takes `passUp` keeps calling its fills: its parameter would hide a `passUp` the fill reads
			      // from the caller's scope.
			      !dispatcher.takesPassUp,
			      // A fill handed the struct of its own level by a level function on a carried route takes it as a parameter.
			      dispatcher.carriedInnerScopes.isEmpty || child.fillCallerReads.innerScopeParameters.isEmpty,
			      // A `@Sendable` dispatcher holds only a `@Sendable` fill's body, and a fill other than `@Sendable` only in a
			      // dispatcher that is not.
			      sendableFillKeys.contains(key) == sendableFillKeys.contains(dispatcher.key)
			else { return nil }
			return key
		})
		return (namedFillKeys, inlinableFillKeys)
	}

	@inline(never)
	nonisolated private static func deferredFillLabels(
		children: [ScopeGenerator],
		previousPassFillSendableWrapperReads: [String: [String: Property]],
		previousPassFillLabelsReadOnlyAsPlaceField: [String: Set<String>],
	) -> (hiddenByReenteringCalls: [String: Set<String>], readInsideSendableFunction: [String: Set<String>], sendableWrapperReads: [String: [String: Property]], readOnlyAsPlaceField: [String: Set<String>], fillStructBoundLabelsChangedInTree: Bool) {
		// A call's fills whose hole has a field bound from a deferred parameter read it from the caller's scope, unless a
		// call inside one of them passes it on beneath another declaration of the label. Nearly no scope calls such a seam.
		// A field every route hands as a carried level's memo is bound from what the fill is handed, never read from the caller.
		let fillsWithDeferredFields = children.compactMap { fill -> (fill: ScopeGenerator, key: String)? in
			// A fill of a case nested by type binds a level's field where a route holds one, whatever another route's deferred one.
			guard let key = fill.fillKey, !fill.fillBindsDeferredFieldsFromStruct, fill.fillFields.contains(where: { $0.isDeferredParameter && !fill.fillLabelsHandedAsMemo.contains($0.property.label) }) else { return nil }
			return (fill, key)
		}
		var fillDeferredLabelsHiddenByReenteringCalls = [String: Set<String>]()
		var fillStructBoundLabelsChangedInTree = children.contains(where: \.fillStructBoundLabelsChangedInTree)
		if !fillsWithDeferredFields.isEmpty {
			let hiddenByFillKey = DependencyTreeGenerator.hiddenByReenteringCalls(ofFills: children)
			for (fill, key) in fillsWithDeferredFields {
				let deferredLabels = Set(fill.fillFields.filter(\.isDeferredParameter).map(\.property.label)).subtracting(fill.fillLabelsHandedAsMemo)
				let hiddenLabels = deferredLabels.intersection(hiddenByFillKey[key].map { Set($0.pathDeclarations.keys) } ?? [])
				if !hiddenLabels.isEmpty {
					fillDeferredLabelsHiddenByReenteringCalls[key] = hiddenLabels
				}
				if fill.fillStructBoundLabels.intersection(deferredLabels) != hiddenLabels {
					fillStructBoundLabelsChangedInTree = true
				}
			}
		}
		// A fill binds a deferred parameter's field it reads from the struct as the seam's memo, so the value is created when
		// its tree reads it, as inline – except a label its tree reads inside a `@Sendable` function where the memo is a
		// `LazilyInstantiated`, which no `@Sendable` function can capture: a deliberate gap, the fill binds the struct's by-value
		// member, which creates the value where the fill, or a level function on its route, is handed the struct (see
		// `Scope.fillUnderConstruction`). Nearly no scope calls such a seam.
		let fillsBindingNonSendableMemos = children.compactMap { fill -> (fill: ScopeGenerator, key: String, labels: Set<String>)? in
			guard let key = fill.fillKey else { return nil }
			let labels = Set(fill.fillFields.filter { $0.deferral == .deferred(isSendable: false) && fill.fillStructBoundLabels.contains($0.property.label) }.map(\.property.label))
			return labels.isEmpty ? nil : (fill, key, labels)
		}
		var fillDeferredLabelsReadInsideSendableFunction = [String: Set<String>]()
		for (fill, key, nonSendableMemoLabels) in fillsBindingNonSendableMemos {
			let labelsReadInsideSendableFunction = fill.labelsReadInsideSendableFunction(among: nonSendableMemoLabels)
			if !labelsReadInsideSendableFunction.isEmpty {
				fillDeferredLabelsReadInsideSendableFunction[key] = labelsReadInsideSendableFunction
			}
			if fill.fillFields.contains(where: { $0.bindsMemo && labelsReadInsideSendableFunction.contains($0.property.label) }) {
				fillStructBoundLabelsChangedInTree = true
			}
		}
		// A fill some route hands the memo of a label its tree reads only as the place's own field of it, the wrapper a type
		// further out declares, never as the memo's value nor at a site of its tree, takes that field on the next pass, as
		// inline reads that declaration (`fillLabelsReadOnlyAsPlaceField`). A label once found stays found: no memo is handed
		// on a later pass to show it. Nearly no scope calls such a seam.
		var fillLabelsReadOnlyAsPlaceField = previousPassFillLabelsReadOnlyAsPlaceField
		for fill in children where !fill.fillLabelsHandedAsMemo.isEmpty {
			guard let key = fill.fillKey, let built = fill.children.first else { continue }
			for field in fill.fillFields where fill.fillLabelsHandedAsMemo.contains(field.property.label) && !built.reads(field.property) && !built.fieldsCarriedBySites.contains(field.property) {
				let placeField = fill.fillCaseHoles.lazy.flatMap(\.fields).first { $0.property.label == field.property.label }
				if let placeField, built.reads(placeField.property) {
					fillLabelsReadOnlyAsPlaceField[key, default: []].insert(field.property.label)
				}
			}
		}
		if fillLabelsReadOnlyAsPlaceField != previousPassFillLabelsReadOnlyAsPlaceField {
			fillStructBoundLabelsChangedInTree = true
		}
		// A fill some route hands the memo of a label its tree also reads as a `SendableLazilyInstantiated` takes that wrapper
		// as the memo where every route can hand it (`FillDispatcher.memosHanded(toFillOf:labels:readingSendableWrapper:among:)`):
		// the pass before finds those reads. Nearly no scope calls such a seam. A read of the optional wrapper only if available
		// is left out: no one parameter takes it together with the memo's instance, so `DependencyTreeGenerator.validateFills`
		// reports the deferring seam's tree receiving the label in two forms (`parameterReceivedInAnotherForm`), as one module
		// reports that seam. So is a label the fill takes as the place's field.
		var fillSendableWrapperReads = [String: [String: Property]]()
		for fill in children where !fill.fillLabelsHandedAsMemo.isEmpty {
			guard let key = fill.fillKey, let built = fill.children.first else { continue }
			var instancePropertyByLabel = [String: Property]()
			let labelsReadOnlyAsPlaceField = fillLabelsReadOnlyAsPlaceField[key] ?? []
			for property in built.receivedProperties.sorted() where fill.fillLabelsHandedAsMemo.contains(property.label) && !labelsReadOnlyAsPlaceField.contains(property.label) && property.propertyType == .sendableLazilyInstantiated && !property.typeDescription.isOptional && instancePropertyByLabel[property.label] == nil {
				instancePropertyByLabel[property.label] = property.asLazilyInstantiatedInstanceProperty
			}
			if !instancePropertyByLabel.isEmpty {
				fillSendableWrapperReads[key] = instancePropertyByLabel
			}
		}
		// The fills were built with the reads the pass before found.
		if fillSendableWrapperReads != previousPassFillSendableWrapperReads {
			fillStructBoundLabelsChangedInTree = true
		}
		return (fillDeferredLabelsHiddenByReenteringCalls, fillDeferredLabelsReadInsideSendableFunction, fillSendableWrapperReads, fillLabelsReadOnlyAsPlaceField, fillStructBoundLabelsChangedInTree)
	}

	@inline(never)
	nonisolated private static func onlyIfAvailableDependencies(
		of dependencies: [Dependency],
		cycleParameters: [CycleParameter],
	) -> [OnlyIfAvailableDependency] {
		dependencies.compactMap { dependency in
			switch dependency.source {
			case let .received(onlyIfAvailable):
				onlyIfAvailable
					? OnlyIfAvailableDependency(
						unwrappedFulfillingProperty: dependency.property.asUnwrappedProperty,
						unavailableProperties: [dependency.property],
					)
					: nil
			case let .aliased(fulfillingProperty, _, onlyIfAvailable):
				// The alias is declared either way – bound to `nil` where its fulfilling property is unavailable – and the
				// type declaring it is passed the alias.
				onlyIfAvailable
					? OnlyIfAvailableDependency(unwrappedFulfillingProperty: fulfillingProperty.asUnwrappedProperty, unavailableProperties: [fulfillingProperty])
					: nil
			case .instantiated, .forwarded:
				nil
			}
		} + cycleParameters.compactMap { parameter in
			// A parameter of the builder function a lazy cycle closes on that no receiver requires is passed `nil` where
			// the scope that would pass it generates its nearest declaration after this scope.
			parameter.isRequired
				? nil
				: OnlyIfAvailableDependency(unwrappedFulfillingProperty: parameter.property.asUnwrappedProperty, unavailableProperties: [parameter.property])
		}
	}

	/// Whether a property a child requires be passed in must be received by a scope too: the scope does not provide it.
	nonisolated private static func isReceivedFromAncestors(
		_ property: Property,
		propertiesToDeclare: Set<Property>,
		forwardedProperties: Set<Property>,
	) -> Bool {
		!provides(property, declaredProperties: propertiesToDeclare, forwardedProperties: forwardedProperties)
	}

	/// Whether a scope declares or forwards a form of `property` that a receive of it only if available reads (see
	/// `Property.formsReadByOnlyIfAvailableReceive`): the receive reads that nearest declaration, and receives nothing
	/// from the scope's ancestors.
	nonisolated private static func providesAFormReadByOnlyIfAvailableReceive(
		of property: Property,
		propertiesToDeclare: Set<Property>,
		forwardedProperties: Set<Property>,
	) -> Bool {
		property.formsReadByOnlyIfAvailableReceive.contains { propertiesToDeclare.contains($0) || forwardedProperties.contains($0) }
	}

	/// What a scope receives from its ancestors.
	private struct Receives {
		let receivedProperties: Set<Property>
		let requiredReceivedProperties: Set<Property>
		/// The properties the scope's own dependencies receive.
		let ownReceivedProperties: Set<Property>
	}

	/// - Parameter cycleParameters: For a scope that closes a lazy cycle, the parameters of the function it refers to;
	///   empty otherwise.
	@inline(never)
	nonisolated private static func receives(
		children: [ScopeGenerator],
		ownDependencies: [Dependency],
		receivesPassedNil: Set<Property>,
		propertiesToDeclare: Set<Property>,
		forwardedProperties: Set<Property>,
		aliasBindingDeclaredProperties: Set<Property>,
		cycleParameters: [CycleParameter],
	) -> Receives {
		// All the properties our children require be passed in, unioned with the properties we
		// require to fulfill our own dependencies, and those of them some receiver requires. A
		// child's required properties are among its received ones, so each child's received
		// properties are read once, with no intermediate sets: this runs at every scope of every tree.
		var receivedProperties = Set<Property>()
		var requiredReceivedProperties = Set<Property>()
		for child in children {
			for property in child.receivedProperties where isReceivedFromAncestors(property, propertiesToDeclare: propertiesToDeclare, forwardedProperties: forwardedProperties) {
				let isRequired = child.requiredReceivedProperties.contains(property)
				guard isRequired || !providesAFormReadByOnlyIfAvailableReceive(of: property, propertiesToDeclare: propertiesToDeclare, forwardedProperties: forwardedProperties) else { continue }
				receivedProperties.insertKeepingMostExplicitSpelling(property)
				if isRequired {
					requiredReceivedProperties.insert(property)
				}
			}
		}
		// The properties this scope's own dependencies receive.
		var ownReceivedProperties = Set<Property>()
		for dependency in ownDependencies {
			let receivedProperty: Property
			let onlyIfAvailable: Bool
			switch dependency.source {
			case .instantiated, .forwarded:
				continue
			case let .received(isOnlyIfAvailable):
				// A receive a mock passes `nil` reads nothing from above.
				guard !receivesPassedNil.contains(dependency.property) else { continue }
				receivedProperty = dependency.property
				onlyIfAvailable = isOnlyIfAvailable
			case let .aliased(fulfillingProperty, _, isOnlyIfAvailable):
				// If the alias's fulfilling property is locally declared
				// (e.g., as an @Instantiated sibling) or forwarded, the alias
				// binds against that local — it doesn't need to be received.
				// An `onlyIfAvailable` alias binds a local of any form it reads.
				// Nor does one a mock binds to `nil`.
				guard !Self.declaresFulfillingProperty(
					of: fulfillingProperty,
					onlyIfAvailable: isOnlyIfAvailable,
					declaredProperties: aliasBindingDeclaredProperties,
					forwardedProperties: forwardedProperties,
				), !receivesPassedNil.contains(fulfillingProperty) else { continue }
				receivedProperty = ValueSpellings.fulfillingProperty(fulfillingProperty, spelledAsAlias: dependency.property)
				onlyIfAvailable = isOnlyIfAvailable
			}
			receivedProperties.insertKeepingMostExplicitSpelling(receivedProperty)
			ownReceivedProperties.insert(receivedProperty)
			if !onlyIfAvailable {
				requiredReceivedProperties.insert(receivedProperty)
			}
		}
		// A scope that closes a lazy cycle passes the function it refers to what that function's body receives under each
		// parameter's label, so it receives those forms as the body does.
		for parameter in cycleParameters {
			receivedProperties.formUnionKeepingMostExplicitSpelling(parameter.receivedForms)
			requiredReceivedProperties.formUnion(parameter.requiredForms)
		}
		return Receives(
			receivedProperties: receivedProperties,
			requiredReceivedProperties: requiredReceivedProperties,
			ownReceivedProperties: ownReceivedProperties,
		)
	}

	@inline(never)
	nonisolated private static func publicMockCallReceives(
		children: [ScopeGenerator],
		ownDependencies: [Dependency],
		publicMockCall: PublicMockCall?,
		ownReceivedProperties: Set<Property>,
		propertiesToDeclare: Set<Property>,
		forwardedProperties: Set<Property>,
	) -> (receivedOnlyByPublicMockCalls: Set<Property>, passedByPublicMockCalls: Set<Property>) {
		// The properties only the leaves that call another module's public mock receive: each receives them only if
		// available, and passes them where the tree provides them. Nearly every subtree calls no public mock.
		var receivedOnlyByPublicMockCalls = Set<Property>()
		if publicMockCall != nil {
			for dependency in ownDependencies where dependency.source == .received(onlyIfAvailable: true) {
				receivedOnlyByPublicMockCalls.insert(dependency.property)
			}
		}
		for child in children {
			for property in child.receivedOnlyByPublicMockCalls where isReceivedFromAncestors(property, propertiesToDeclare: propertiesToDeclare, forwardedProperties: forwardedProperties) {
				receivedOnlyByPublicMockCalls.insert(property)
			}
		}
		if !receivedOnlyByPublicMockCalls.isEmpty {
			// A property another receiver receives is not only the leaves'.
			for child in children {
				receivedOnlyByPublicMockCalls.subtract(child.receivedProperties.subtracting(child.receivedOnlyByPublicMockCalls))
			}
			if publicMockCall == nil {
				receivedOnlyByPublicMockCalls.subtract(ownReceivedProperties)
			}
		}
		// Of those, the ones some call passes: the tier it reaches takes them. Others are omitted by every call.
		var passedByPublicMockCalls = Set<Property>()
		if !receivedOnlyByPublicMockCalls.isEmpty {
			if let publicMockCall {
				for parameter in publicMockCall.passedParameters where parameter.dependency.source == .received(onlyIfAvailable: true) {
					passedByPublicMockCalls.insert(parameter.dependency.property)
				}
			}
			for child in children {
				passedByPublicMockCalls.formUnion(child.passedByPublicMockCalls)
			}
			passedByPublicMockCalls.formIntersection(receivedOnlyByPublicMockCalls)
		}
		return (receivedOnlyByPublicMockCalls, passedByPublicMockCalls)
	}

	/// - Parameter cycleParameters: For a scope that closes a lazy cycle, the parameters of the function it refers to;
	///   empty otherwise.
	@inline(never)
	nonisolated private static func aliasRequirements(
		children: [ScopeGenerator],
		propertiesToDeclare: Set<Property>,
		forwardedProperties: Set<Property>,
		cycleParameters: [CycleParameter],
		seamCall: SeamCall?,
	) -> (requiredOnlyIfAvailableAliasProperties: Set<Property>, requiredAliasFulfillingProperties: Set<Property>) {
		// A child's tree requires an `onlyIfAvailable` alias this scope declares when a receiver in it requires the alias's
		// property, or an alias in it that is required is fulfilled by that property. The alias is bound from the nearest
		// declaration of its fulfilling property's label, so that declaration is built first: a sibling here (see
		// `orderedPropertiesToGenerate`), or, where this scope declares none, one an enclosing scope declares, which this
		// scope's `requiredAliasFulfillingProperties` carries up until a scope declares the label. No alias of a scope
		// renames another (SafeDITool rejects that before it validates a tree that builds the scope), so a child's
		// requirement is the only way.
		func isRequiredByChild(_ property: Property) -> Bool {
			children.contains { child in
				child.requiredReceivedProperties.contains(property)
					|| child.requiredAliasFulfillingProperties.contains { $0.label == property.label && provides(property, aFormReadBy: $0) }
			}
		}
		var requiredOnlyIfAvailableAliasProperties = Set<Property>()
		var requiredOnlyIfAvailableAliasFulfillingProperties = Set<Property>()
		for case let (aliasProperty?, fulfillingProperty?) in children.lazy.map({ ($0.property, $0.onlyIfAvailableAliasFulfillingProperty) })
			where isRequiredByChild(aliasProperty)
		{
			requiredOnlyIfAvailableAliasProperties.insert(aliasProperty)
			requiredOnlyIfAvailableAliasFulfillingProperties.insert(fulfillingProperty)
		}
		// A requirement stops at the nearest declaration of its label, whatever form that declaration has: the alias reads
		// it, or is `nil` where it provides no form the alias reads.
		var declaredLabels = Set(forwardedProperties.map(\.label))
		for declaredProperty in propertiesToDeclare {
			declaredLabels.insert(declaredProperty.label)
		}
		// A call of a seam whose tree requires one of its pass-throughs through an `onlyIfAvailable` alias requires it too
		// (`SeamSignature.Parameter.requiredThroughAlias`): the seam's alias is bound from that parameter. Validation reads
		// the same requirement from the seam's tree, which it walks inline, so `collectReceivedProperties` meets no seam call.
		let requiredAliasFulfillingProperties = Set(children.flatMap(\.requiredAliasFulfillingProperties))
			.union(requiredOnlyIfAvailableAliasFulfillingProperties)
			.union(cycleParameters.flatMap(\.requiredAliasFulfillingForms))
			.union(seamCall?.requiredThroughAliasProperties ?? [])
			.filter { !declaredLabels.contains($0.label) }
		return (requiredOnlyIfAvailableAliasProperties, requiredAliasFulfillingProperties)
	}

	/// - Parameter cycleParameters: For a scope that closes a lazy cycle, the parameters of the function it refers to;
	///   empty otherwise.
	@inline(never)
	nonisolated private static func onlyIfAvailableUnwrappedReceivedProperties(
		children: [ScopeGenerator],
		ownDependencies: [Dependency],
		receivesPassedNil: Set<Property>,
		propertiesToDeclare: Set<Property>,
		forwardedProperties: Set<Property>,
		aliasBindingDeclaredProperties: Set<Property>,
		cycleParameters: [CycleParameter],
		requiredReceivedProperties: Set<Property>,
	) -> Set<Property> {
		var onlyIfAvailableUnwrappedReceivedPropertiesIncludingRequired = Set<Property>()
		for propertyToGenerate in children {
			for property in propertyToGenerate.onlyIfAvailableUnwrappedReceivedProperties
				where !providesAFormReadByOnlyIfAvailableReceive(of: property, propertiesToDeclare: propertiesToDeclare, forwardedProperties: forwardedProperties)
			{
				onlyIfAvailableUnwrappedReceivedPropertiesIncludingRequired.insert(property)
			}
		}
		for dependency in ownDependencies {
			switch dependency.source {
			case .instantiated, .forwarded:
				continue
			case let .received(onlyIfAvailable):
				guard onlyIfAvailable, !receivesPassedNil.contains(dependency.property) else { continue }
				onlyIfAvailableUnwrappedReceivedPropertiesIncludingRequired.insert(dependency.property.asUnwrappedProperty)
			case let .aliased(fulfillingProperty, _, onlyIfAvailable):
				// Skip locally-declared and forwarded fulfilling properties —
				// the alias binds to the local, not to an ancestor – and those a mock binds the alias `nil` for.
				guard onlyIfAvailable, !Self.declaresFulfillingProperty(
					of: fulfillingProperty,
					onlyIfAvailable: true,
					declaredProperties: aliasBindingDeclaredProperties,
					forwardedProperties: forwardedProperties,
				), !receivesPassedNil.contains(fulfillingProperty) else { continue }
				onlyIfAvailableUnwrappedReceivedPropertiesIncludingRequired.insert(fulfillingProperty.asUnwrappedProperty)
			}
		}
		for parameter in cycleParameters {
			onlyIfAvailableUnwrappedReceivedPropertiesIncludingRequired.formUnion(parameter.onlyIfAvailableUnwrappedForms)
		}
		// A property some receiver requires is required, even where others receive
		// it only if available. Few subtrees receive anything only if available, so the
		// required properties are unwrapped only for those that do.
		return onlyIfAvailableUnwrappedReceivedPropertiesIncludingRequired.isEmpty
			? onlyIfAvailableUnwrappedReceivedPropertiesIncludingRequired
			: onlyIfAvailableUnwrappedReceivedPropertiesIncludingRequired.subtracting(requiredReceivedProperties.map(\.asUnwrappedProperty))
	}

	/// The parameters of the builder function a lazy cycle closes on that a scope finds, and what it carries up for them.
	private struct CycleParameterSearch {
		let cycleClosingRedeclaredLabels: [BuiltDeclaration: [String: CycleParameter.Redeclaration]]
		let foundCycleParameters: [CycleParameter]
		let unpassableCycleLabelsInTree: [UnpassableCycleLabel]
	}

	@inline(never)
	nonisolated private static func cycleParameterSearch(
		instantiable: Instantiable,
		property: Property?,
		declaration: BuiltDeclaration?,
		closedOnDeclaration: BuiltDeclaration?,
		isPropertyCycle: Bool,
		childrenTakePartInCycle: Bool,
		children: [ScopeGenerator],
		propertiesToDeclare: Set<Property>,
		forwardedProperties: Set<Property>,
		cycleParameters: [CycleParameter],
		receivedProperties: Set<Property>,
		requiredReceivedProperties: Set<Property>,
		requiredAliasFulfillingProperties: Set<Property>,
		onlyIfAvailableUnwrappedReceivedProperties: Set<Property>,
	) -> CycleParameterSearch {
		// The labels the scopes between each cycle-closing scope in this subtree and the scope it closes on declare, by the
		// declaration the cycle closes on. A scope a cycle closes on takes those of them its tree receives from the scopes
		// enclosing it as parameters of its builder function. Nearly every scope takes part in no cycle.
		var cycleClosingRedeclaredLabels = [BuiltDeclaration: [String: CycleParameter.Redeclaration]]()
		if let closedOnDeclaration {
			cycleClosingRedeclaredLabels[closedOnDeclaration] = [:]
		} else if childrenTakePartInCycle {
			for child in children {
				for (closedOnDeclaration, redeclarations) in child.cycleClosingRedeclaredLabels {
					cycleClosingRedeclaredLabels[closedOnDeclaration, default: [:]].merge(redeclarations) { $0.preceding($1) }
				}
			}
		}
		var foundCycleParameters = [CycleParameter]()
		var unpassableCycleLabelsInTree = [UnpassableCycleLabel]()
		if let property, let declaration, !isPropertyCycle, let redeclarations = cycleClosingRedeclaredLabels.removeValue(forKey: declaration) {
			// The property's own label is no parameter: the function's body is passed `nil` for it wherever it is called,
			// since every call is made inside the tree that builds a declaration of the label – the property itself where
			// the function is declared, and the cycle-closing scope's own property where it closes the cycle. Nor is a label
			// this scope declares or forwards itself: inside the function its own declaration is the nearest of the label,
			// so a parameter of the label would be a second declaration of a forwarded property, or hidden by the body's
			// own. A receive of a form that declaration does not provide is judged as outside a cycle, by
			// `DependencyTreeGenerator`'s `validateTreeBuiltAgainByCycle`.
			var ownDeclaredLabels: Set<String> = [property.label]
			for declaredProperty in propertiesToDeclare {
				ownDeclaredLabels.insert(declaredProperty.label)
			}
			for forwardedProperty in forwardedProperties {
				ownDeclaredLabels.insert(forwardedProperty.label)
			}
			var receivedRedeclarations = [String: CycleParameter.Redeclaration]()
			for receivedProperty in receivedProperties where !ownDeclaredLabels.contains(receivedProperty.label) {
				receivedRedeclarations[receivedProperty.label] = redeclarations[receivedProperty.label]
			}
			if !receivedRedeclarations.isEmpty {
				(foundCycleParameters, unpassableCycleLabelsInTree) = CycleParameter.parameters(
					firstReceives: inOrderTheBodyFirstReceives(
						ofLabels: receivedRedeclarations,
						builtProperty: property,
						builtDeclaration: declaration,
						builtType: instantiable.concreteInstantiable,
						ownDependencies: instantiable.dependencies,
						children: children,
					).map { (label: $0.label, receiver: $0.receiver, redeclaration: $0.value) },
					receivedProperties: receivedProperties,
					requiredReceivedProperties: requiredReceivedProperties,
					requiredAliasFulfillingProperties: requiredAliasFulfillingProperties,
					onlyIfAvailableUnwrappedReceivedProperties: onlyIfAvailableUnwrappedReceivedProperties,
					builtType: instantiable.concreteInstantiable,
				)
			}
		}
		for child in children where !child.unpassableCycleLabelsInTree.isEmpty {
			unpassableCycleLabelsInTree.append(contentsOf: child.unpassableCycleLabelsInTree)
		}
		if !isPropertyCycle, !cycleClosingRedeclaredLabels.isEmpty {
			// This scope's declarations, forwarded properties and own parameters are between each of those cycle-closing
			// scopes and the scope it closes on. A declaration is noted at the dependency that declares its label, and a
			// parameter at the declaration that made it one.
			var redeclarations = [String: CycleParameter.Redeclaration]()
			for declaredProperty in propertiesToDeclare.union(forwardedProperties) {
				let dependency = instantiable.dependencies.first { !$0.source.isReceived && $0.property.label == declaredProperty.label }
				let redeclaration = CycleParameter.Redeclaration(
					property: dependency?.property ?? declaredProperty,
					declaringType: instantiable.concreteInstantiable,
					declarationLocation: dependency?.declarationLocation,
				)
				redeclarations[declaredProperty.label] = redeclarations[declaredProperty.label].map { $0.preceding(redeclaration) } ?? redeclaration
			}
			for parameter in cycleParameters {
				redeclarations[parameter.property.label] = redeclarations[parameter.property.label].map { $0.preceding(parameter.redeclaration) } ?? parameter.redeclaration
			}
			cycleClosingRedeclaredLabels = cycleClosingRedeclaredLabels.mapValues { $0.merging(redeclarations) { $0.preceding($1) } }
		}
		return CycleParameterSearch(
			cycleClosingRedeclaredLabels: cycleClosingRedeclaredLabels,
			foundCycleParameters: foundCycleParameters,
			unpassableCycleLabelsInTree: unpassableCycleLabelsInTree,
		)
	}

	/// The properties the builder function of a member of a loop of builders rebinds (see `reboundProperties`).
	@inline(never)
	nonisolated private static func reboundProperties(
		_ reboundProperties: Set<Property>,
		builtProperty property: Property,
		builtDeclaration declaration: BuiltDeclaration,
		instantiable: Instantiable,
		children: [ScopeGenerator],
		forwardedProperties: Set<Property>,
		cycleParameters: [CycleParameter],
	) -> [Property] {
		// The function rebinds what its tree receives inside its loop, in the order its body first receives each, except a
		// label its own parameters name: the body reads the parameter.
		var parameterLabels = Set(forwardedProperties.map(\.label))
		for parameter in cycleParameters {
			parameterLabels.insert(parameter.property.label)
		}
		// The forms of each label, in property order.
		var reboundFormsByLabel = [String: [Property]]()
		for reboundProperty in reboundProperties.sorted() where !parameterLabels.contains(reboundProperty.label) {
			reboundFormsByLabel[reboundProperty.label, default: []].append(reboundProperty)
		}
		let firstReceives = inOrderTheBodyFirstReceives(
			ofLabels: reboundFormsByLabel,
			builtProperty: property,
			builtDeclaration: declaration,
			builtType: instantiable.concreteInstantiable,
			ownDependencies: instantiable.dependencies,
			children: children,
		)
		// Every label rebound is received in the body, so the walk meets each.
		return firstReceives.flatMap(\.value)
	}

	init(
		property: Property,
		fulfillingProperty: Property,
		fulfillingPropertyIsLazilyInstantiatedInstance: Bool,
		unavailableOptionalProperties: Set<Property>,
		fulfillingPropertyIsPassedNil: Bool = false,
		erasedToConcreteExistential: Bool,
		onlyIfAvailable: Bool,
		fulfillingBindingIsOptional: Bool,
		fulfillingExpression: String? = nil,
		declarationReference: AliasDeclarationReferences.Reference?,
	) {
		self.fulfillingExpression = fulfillingExpression
		scopeData = .alias(
			property: property,
			fulfillingProperty: fulfillingProperty,
			erasedToConcreteExistential: erasedToConcreteExistential,
			onlyIfAvailable: onlyIfAvailable,
			declarationReference: declarationReference,
		)
		// An alias a mock binds to `nil`, as production always does, reads nothing from above (see `receivesPassedNil` of
		// the scope that declares it). It receives its fulfilling property as its own property spells it
		// (`ValueSpellings.fulfillingProperty(_:spelledAsAlias:)`).
		receivedProperties = fulfillingPropertyIsPassedNil ? [] : [ValueSpellings.fulfillingProperty(fulfillingProperty, spelledAsAlias: property)]
		receivedOnlyByPublicMockCalls = []
		passedByPublicMockCalls = []
		if onlyIfAvailable {
			requiredReceivedProperties = []
			unwrappedOptionalRequiredReceivedProperties = []
			onlyIfAvailableUnwrappedReceivedProperties = fulfillingPropertyIsPassedNil ? [] : [fulfillingProperty.asUnwrappedProperty]
			onlyIfAvailableDependencies = [OnlyIfAvailableDependency(unwrappedFulfillingProperty: fulfillingProperty.asUnwrappedProperty, unavailableProperties: [fulfillingProperty])]
		} else {
			requiredReceivedProperties = [fulfillingProperty]
			unwrappedOptionalRequiredReceivedProperties = fulfillingProperty.typeDescription.isOptional ? [fulfillingProperty.asUnwrappedProperty] : []
			onlyIfAvailableUnwrappedReceivedProperties = []
			onlyIfAvailableDependencies = []
		}
		// An `onlyIfAvailable` alias is ordered after the sibling that declares its fulfilling property where that closes
		// no cycle, so it is bound from that sibling.
		onlyIfAvailableAliasFulfillingProperty = onlyIfAvailable ? fulfillingProperty : nil
		self.fulfillingBindingIsOptional = onlyIfAvailable && fulfillingBindingIsOptional
		requiredOnlyIfAvailableAliasProperties = []
		requiredAliasFulfillingProperties = []
		cycleClosedOnDeclarations = []
		isReferencedByCycleClosingScope = false
		closedOnDeclaration = nil
		declaration = nil
		cycleClosedOnDeclarationsReferencedFromSendableFunction = []
		buildsInSendableFunction = false
		declaresBuilderFunction = false
		childrenTakePartInCycle = false
		typesDeclaredEscaping = []
		cycleParameters = []
		cycleParameterUnavailableProperties = []
		callSiteLazilyInstantiatedInstanceProperties = []
		cycleClosingRedeclaredLabels = [:]
		foundCycleParameters = []
		unpassableCycleLabelsInTree = []
		cycleParametersChangedInTree = false
		receivedBuilderLoops = ReceivedBuilderLoops()
		receivedBuilderLoopsChangedInTree = false
		boxedLoops = [:]
		loopLevelsTypesInTree = [:]
		publicMockLevelReentries = [:]
		publicMockLevelReentriesChangedInTree = false
		reboundProperties = []
		description = property.asSource
		propertiesToGenerate = []
		propertiesToDeclare = []
		instantiatedDependenciesNotGenerated = []
		self.unavailableOptionalProperties = unavailableOptionalProperties
		lazilyInstantiatedInstanceProperties = []
		self.fulfillingPropertyIsLazilyInstantiatedInstance = fulfillingPropertyIsLazilyInstantiatedInstance
		declaredLazilyInstantiatedInstanceProperty = property.asLazilyInstantiatedInstancePropertyOfDeclaredBinding
		self.property = property
		// An alias constructs nothing.
		builtInlineSeamComment = nil
		publicMockCall = nil
		mockBuilders = nil
		namesBoundBySeam = []
		ownerPropertyStack = []
		ownerConcreteTypeStack = []
		holeCallArguments = []
		builderCallArguments = []
		fillDispatchers = []
		publicMockLevelFunctions = nil
		passedUpHoles = []
		valuesBindings = []
		memberCallsInsideFunction = []
		sendableFunctionsAreNonisolated = false
		isBuiltByFill = false
		fillReturnsWrapperBuilder = false
		innerScopesCalledWithForwardedValue = []
		containsBuildSite = false
		placeHoldingProperties = nil
		fieldsCarriedBySites = []
		passesUpBuilder = false
		holdsCallReenteringEnclosingFill = false
		fillKey = nil
		closedOnFillPathDeclarationsBeneath = nil
		fillStructBoundLabels = []
		fillBindsDeferredFieldsFromStruct = false
		fillLabelsHandedAsMemo = []
		fillPlainMemoRoutesOfSendableWrapperReads = [:]
		fillMemoOriginsByLabel = [:]
		fillFields = []
		fillCaseHoles = []
		fillEmitsCode = true
		fillCallerReads = FillCallerReads()
		fillDeferredLabelsHiddenByReenteringCalls = [:]
		fillDeferredLabelsReadInsideSendableFunction = [:]
		fillSendableWrapperReads = [:]
		fillLabelsReadOnlyAsPlaceField = [:]
		fillStructBoundLabelsChangedInTree = false
		constructsWithHandWrittenMock = false
		referencedFillNamesByKey = [:]
		fillKeysReferencedFromSendableFunction = []
		sendableFillKeys = []
		inlinableFillKeys = []
		namedFillKeys = []
	}

	/// The generator of a hole: a site in a seam's tree of `holeProperty`, which the builder the seam's generated
	/// initializer takes builds from the values in scope there, `site`'s fields. It receives nothing: the scopes
	/// beneath it are the fill's, which the module that fills the builder generates. `site` is `nil` in a tree built
	/// only to compute the seam's signature, which generates nothing. `ownerLazilyInstantiatedInstanceProperties` are the
	/// properties the site's owner holds only as a `LazilyInstantiated` property's instance, which the site's payload
	/// reads as the owner's receivers do.
	init(
		holeProperty: Property,
		erasedToConcreteExistential: Bool,
		site: SeamSignature.Hole?,
		ownerPropertyStack: [Property],
		ownerConcreteTypeStack: [TypeDescription],
		ownerLazilyInstantiatedInstanceProperties: Set<Property> = [],
		sendableFunctionsAreNonisolated: Bool,
	) {
		scopeData = .hole(property: holeProperty, erasedToConcreteExistential: erasedToConcreteExistential, site: site)
		self.ownerPropertyStack = ownerPropertyStack
		self.ownerConcreteTypeStack = ownerConcreteTypeStack
		receivedProperties = []
		receivedOnlyByPublicMockCalls = []
		passedByPublicMockCalls = []
		requiredReceivedProperties = []
		unwrappedOptionalRequiredReceivedProperties = []
		onlyIfAvailableUnwrappedReceivedProperties = []
		onlyIfAvailableDependencies = []
		onlyIfAvailableAliasFulfillingProperty = nil
		requiredOnlyIfAvailableAliasProperties = []
		requiredAliasFulfillingProperties = []
		cycleClosedOnDeclarations = []
		isReferencedByCycleClosingScope = false
		closedOnDeclaration = nil
		closedOnFillPathDeclarationsBeneath = nil
		// A site that builds a wrapper declares a builder function, which a cycle-closing scope beneath a sibling must not
		// resolve to. No cycle closes on it: a site has no tree beneath it.
		declaration = holeProperty.propertyType.isConstant ? nil : BuiltDeclaration(property: holeProperty, concreteType: holeProperty.typeDescription.asInstantiatedType)
		cycleClosedOnDeclarationsReferencedFromSendableFunction = []
		buildsInSendableFunction = false
		declaresBuilderFunction = !holeProperty.propertyType.isConstant
		childrenTakePartInCycle = false
		typesDeclaredEscaping = []
		cycleParameters = []
		cycleParameterUnavailableProperties = []
		callSiteLazilyInstantiatedInstanceProperties = ownerLazilyInstantiatedInstanceProperties
		cycleClosingRedeclaredLabels = [:]
		foundCycleParameters = []
		unpassableCycleLabelsInTree = []
		cycleParametersChangedInTree = false
		receivedBuilderLoops = ReceivedBuilderLoops()
		receivedBuilderLoopsChangedInTree = false
		boxedLoops = [:]
		loopLevelsTypesInTree = [:]
		publicMockLevelReentries = [:]
		publicMockLevelReentriesChangedInTree = false
		reboundProperties = []
		description = holeProperty.asSource
		propertiesToGenerate = []
		propertiesToDeclare = []
		instantiatedDependenciesNotGenerated = []
		unavailableOptionalProperties = []
		lazilyInstantiatedInstanceProperties = []
		fulfillingPropertyIsLazilyInstantiatedInstance = false
		fulfillingBindingIsOptional = false
		fulfillingExpression = nil
		declaredLazilyInstantiatedInstanceProperty = holeProperty.asLazilyInstantiatedInstanceProperty
		property = holeProperty
		builtInlineSeamComment = nil
		publicMockCall = nil
		mockBuilders = nil
		namesBoundBySeam = []
		holeCallArguments = []
		builderCallArguments = []
		fillDispatchers = []
		publicMockLevelFunctions = nil
		passedUpHoles = []
		valuesBindings = []
		memberCallsInsideFunction = []
		self.sendableFunctionsAreNonisolated = sendableFunctionsAreNonisolated
		isBuiltByFill = false
		fillReturnsWrapperBuilder = false
		innerScopesCalledWithForwardedValue = []
		containsBuildSite = true
		placeHoldingProperties = nil
		fieldsCarriedBySites = Set((site.map(Self.fieldsCarried(by:)) ?? []).map(\.property))
		passesUpBuilder = false
		holdsCallReenteringEnclosingFill = false
		fillKey = nil
		fillStructBoundLabels = []
		fillBindsDeferredFieldsFromStruct = false
		fillLabelsHandedAsMemo = []
		fillPlainMemoRoutesOfSendableWrapperReads = [:]
		fillMemoOriginsByLabel = [:]
		fillFields = []
		fillCaseHoles = []
		fillEmitsCode = true
		fillCallerReads = FillCallerReads()
		fillDeferredLabelsHiddenByReenteringCalls = [:]
		fillDeferredLabelsReadInsideSendableFunction = [:]
		fillSendableWrapperReads = [:]
		fillLabelsReadOnlyAsPlaceField = [:]
		fillStructBoundLabelsChangedInTree = false
		constructsWithHandWrittenMock = false
		referencedFillNamesByKey = [:]
		fillKeysReferencedFromSendableFunction = []
		sendableFillKeys = []
		inlinableFillKeys = []
		namedFillKeys = []
	}

	/// The generator of a fill: the function the module that calls a seam generates for one of its holes, which binds
	/// the fields of the site's scope struct that `child`, the generator of the hole's property as the fulfilling
	/// type builds it, reads. The fields it binds from the struct, those `boundLabels` names, are declared here, so a
	/// receive they provide is not received from the scopes enclosing the call (see `fillStructBoundLabels`).
	///
	/// A fill of a place whose case is nested by type stands for every place of the case: `fields` are what any of them
	/// carries, and only the first place's fill `emitsCode`, which every route of the case calls. What it reads of the
	/// caller's scope through the root dispatcher (`callerReads`) it receives as its own dependencies, so the caller orders,
	/// and passes `nil` for, each as it would for the tree built inline.
	init(
		fill hole: SeamSignature.Hole,
		key: String,
		functionName: String,
		boundLabels: Set<String>,
		fields: [SeamSignature.Hole.Field],
		caseHoles: [SeamSignature.Hole],
		emitsCode: Bool,
		callerReads: FillCallerReads = FillCallerReads(),
		returnsWrapperBuilder: Bool = false,
		labelsHandedAsMemo: Set<String> = [],
		plainMemoRoutesOfSendableWrapperReads: [String: [FillDispatcher.PlainMemoRoute]] = [:],
		memoOriginsByLabel: [String: [SeamSignature.Hole.Field.SeamParameterOrigin]] = [:],
		child: ScopeGenerator,
	) {
		self.init(
			instantiable: Instantiable(
				instantiableType: hole.property.typeDescription.asInstantiatedType,
				isRoot: false,
				initializer: nil,
				additionalInstantiables: nil,
				dependencies: callerReads.dependencies,
				declarationType: .structType,
				access: AccessDeclaration(level: .internal),
			),
			property: nil,
			propertiesToGenerate: [child],
			propertiesToDeclare: Self.fieldForms(of: fields, boundLabels: boundLabels),
			// A fill builds only `child`, so no dependency of its own is one a mock is passed instead.
			instantiatedDependenciesNotGenerated: [],
			unavailableOptionalProperties: callerReads.unavailableProperties,
			lazilyInstantiatedInstanceProperties: [],
			forwardedLazilyInstantiatedInstanceProperties: [],
			erasedToConcreteExistential: false,
			isPropertyCycle: false,
			builtInlineSeamComment: nil,
			fillReturnsWrapperBuilder: returnsWrapperBuilder,
			fill: (hole, key, functionName, boundLabels, fields, caseHoles, emitsCode, callerReads, labelsHandedAsMemo, plainMemoRoutesOfSendableWrapperReads, memoOriginsByLabel),
		)
	}

	/// What a fill of a case nested by type reads of the caller's scope through the root dispatcher (see
	/// `ScopeGeneratorUnderConstruction.callerReads(of:child:)`).
	struct FillCallerReads: Sendable {
		/// Each form the fill's tree reads of such a label, as a dependency the fill receives: required where the tree
		/// requires it, else only if available.
		var dependencies = [Dependency]()
		/// Those of `dependencies` received only if available that no declaration enclosing the call binds.
		var unavailableProperties = Set<Property>()
		/// The parameter the fill takes for each such label.
		var parameterByLabel = [String: SeamSignature.Hole.Field]()
		/// What the root dispatcher passes the parameter of each such label, where the caller does not build it later.
		var argumentByLabel = [String: String]()
		/// What the root dispatcher hands of each label the fill takes as a `SendableLazilyInstantiated` memo some route hands
		/// it (`Scope.Fill.labelsHandedAsMemo`), by the memo the fill takes (`SeamSignature.Hole.Field.memoProperty`): the
		/// caller's declaration of that wrapper, or one made of the caller's value, so the fill's tree reads the caller's own
		/// wrapper where it reads the wrapper, as inline.
		var memoArgumentByMemo = [Property: String]()
		/// The scope value the inner seam handed the fill, which a place inside its tree, or a call there that passes one up,
		/// carries (`SeamHoles.innerScope(at:innerKey:)`): the fill takes it as a parameter, and each dispatcher that leads to
		/// it passes it on from the root dispatcher's own parameter.
		var innerScopeParameters = [SeamSignature.Hole.Field]()
		/// The property the caller's mock root binds for each caller's own value the fill reads from that binding, by label
		/// (`Scope.Fill.mockRootBindingByLabel`): the fill binds the label to the name the mock spells for the property
		/// (`FillPlaceBindings.rootBindingNames`).
		var mockRootBindingByLabel = [String: Property]()
	}

	/// What one fill binds for every place of a case nested by type: `fields`, one per label some place's struct carries, in
	/// the order the places first carry them, and `callerReadLabels`.
	struct CaseFields: Sendable {
		var fields = [SeamSignature.Hole.Field]()
		/// The labels a level holds on some route to the case and none holds on another, where inline reads the caller's
		/// declaration: the root dispatcher hands the fill the caller's.
		var callerReadLabels = Set<String>()
	}

	/// What one fill binds for every place of `places`, the places of one case nested by type in builder order. A label the
	/// case's payload carries is its payload's field. Any other label is read from the nearest level that holds it on each
	/// route, which a field bound from a deferred parameter is not, since inline reads the caller's declaration there: the
	/// field is that level's, made optional where one route holds it only optionally, so every route can hand it. A
	/// label no level holds on any route keeps its deferred parameter's field, which the fill reads from the caller's
	/// scope directly. Forms of one label that differ in more than optionality are left to `validateFills`
	/// (`FillFinding.Kind.fieldFormsDifferBetweenPlaces`), which `irreconcilableFields(of:)` finds.
	static func caseFields(of places: [SeamSignature.Hole]) -> CaseFields {
		var caseFields = CaseFields()
		guard let firstPlace = places.first else { return caseFields }
		let payloadLabels = Set((firstPlace.enumPlace?.values ?? []).map(\.property.label))
		let fieldsByLabelByPlace = places.map { place in
			Dictionary(place.fields.map { ($0.property.label, $0) }, uniquingKeysWith: { first, _ in first })
		}
		var labels = [String]()
		var seenLabels = Set<String>()
		for place in places {
			for field in place.fields where seenLabels.insert(field.property.label).inserted {
				labels.append(field.property.label)
			}
		}
		for label in labels {
			let held = fieldsByLabelByPlace.compactMap { $0[label] }
			guard !payloadLabels.contains(label) else {
				caseFields.fields += held.prefix(1)
				continue
			}
			let heldByLevels = held.filter { !$0.isDeferredParameter }
			guard let firstHeld = heldByLevels.first else {
				caseFields.fields += held.prefix(1)
				continue
			}
			caseFields.fields.append(heldByLevels.first { $0.property.typeDescription.isOptional && $0.property.asUnwrappedProperty == firstHeld.property.asUnwrappedProperty } ?? firstHeld)
			if heldByLevels.count < places.count {
				caseFields.callerReadLabels.insert(label)
			}
		}
		return caseFields
	}

	/// The fields of `places`, the places of one case nested by type, whose label some of them carry in forms that differ in
	/// more than optionality, from levels: one fill cannot take them as one parameter. Each label's forms in the order of
	/// their declarations' locations, so the one a diagnostic is reported at never depends on a type's name.
	static func irreconcilableFields(of places: [SeamSignature.Hole]) -> [String: [SeamSignature.Hole.Field]] {
		guard let firstPlace = places.first else { return [:] }
		let payloadLabels = Set((firstPlace.enumPlace?.values ?? []).map(\.property.label))
		var fieldsByLabel = [String: [Property: SeamSignature.Hole.Field]]()
		for place in places {
			for field in place.fields where !field.isDeferredParameter && !payloadLabels.contains(field.property.label) {
				fieldsByLabel[field.property.label, default: [:]][field.property] = fieldsByLabel[field.property.label]?[field.property] ?? field
			}
		}
		return fieldsByLabel.compactMapValues { fieldsByProperty in
			guard Set(fieldsByProperty.keys.map(\.asUnwrappedProperty)).count > 1 else { return nil }
			// Each field a place carries is a declaration's, at its own location (`SeamBuilderParameters.fields(of:)`), so the
			// locations order the forms. The forms are put in property order first, which the stable sort keeps among any
			// two at one location, so the order never depends on the dictionary's.
			return fieldsByProperty
				.sorted { $0.key < $1.key }
				.map(\.value)
				.sorted { Dependency.DeclarationLocation.precedesInSourceOrder($0.declarationLocation, $1.declarationLocation) }
		}
	}

	/// The properties a fill of `hole` declares: the property of each field of the site's scope struct it binds – each
	/// labeled in `boundLabels` – and, for a lazily instantiated field, the instance a receive reads by value.
	static func fieldForms(of hole: SeamSignature.Hole, boundLabels: Set<String>) -> Set<Property> {
		fieldForms(of: hole.fields, boundLabels: boundLabels)
	}

	/// The properties a fill declares that binds those of `fields` labeled in `boundLabels` (see `fieldForms(of:boundLabels:)`).
	static func fieldForms(of fields: [SeamSignature.Hole.Field], boundLabels: Set<String>) -> Set<Property> {
		var fieldForms = Set<Property>()
		for field in fields where boundLabels.contains(field.property.label) {
			fieldForms.insert(field.property)
			if let instanceProperty = field.property.asLazilyInstantiatedInstancePropertyOfDeclaredBinding {
				fieldForms.insert(instanceProperty)
			}
		}
		return fieldForms
	}

	/// The name of the function a caller generates to fill `hole`'s builder, unless a name of the scope it is declared in
	/// has that name (see `ScopeGeneratorUnderConstruction`).
	static func fillFunctionName(of hole: SeamSignature.Hole) -> String {
		// A fill's hole is a place of a seam whose builders are shaped, so it has its case nested by type (`enumPlace`),
		// whose enum `scopeTypeName` names. Joined unspelled, then spelled once: a seam's stem can be a raw identifier's
		// text. A case nested in the root is named after its enum too.
		let enumName = hole.enumPlace?.rootEnumTypeName == nil ? "" : "\(hole.scopeTypeName)_"
		let caseName = hole.enumPlace?.caseName ?? ""
		return functionName(toBuildPropertyNamed: "\(hole.builderLabel.spelledWithoutBackticks)_\(DependencyTreeGenerator.seamStem(of: hole.scopeSeamType))_\(enumName)\(caseName.spelledWithoutBackticks)".spelledAsIdentifier)
	}

	/// What a seam call passes one builder: the label it takes it under and the expression passed.
	struct BuilderCallArgument: Sendable {
		init(label: String, value: String, enclosingFill: EnclosingFill? = nil, isSendable: Bool = false, builderStruct: PublicMockBuilderStruct? = nil, overrideHanding: OverrideHanding = .none) {
			self.label = label
			self.value = value
			self.enclosingFill = enclosingFill
			self.isSendable = isSendable
			self.builderStruct = builderStruct
			self.overrideHanding = overrideHanding
		}

		/// What a call of another module's public mock can hand an override closure that builds the called mock for one of
		/// its builders, which the closure passes on to the called `mock()`: a builder a person writes.
		enum OverrideHanding: Sendable {
			/// Nothing a person writes: the call is made in a public mock's body, which holds only the builder struct its
			/// caller built, and passes the builder up whole.
			case none
			/// The builder the calling internal mock takes, `value`, which it passes up whole.
			case callersBuilder
			/// A function over the call's fill, where the root level function's every member fills the one place the builder
			/// reaches: a call that passes a place up, or fills some places and passes others up, offers none
			/// (`publicMockOverrideBuilders`).
			case fills
		}

		/// What a call passes a public mock's builder: the call of the root level function of the dispatcher of
		/// `rootDispatcherKey` (`PublicMockLevelFunctions`), or, where the call fills no place of the builder, `upValue` itself.
		struct PublicMockBuilderStruct: Sendable {
			/// The key of the dispatcher whose level function the call passes, or `nil` where the call fills no place of the
			/// builder.
			let rootDispatcherKey: String?
			/// The struct the caller passes up, of the called mock's root level: the member of the caller's own struct, or the
			/// struct of the builder the caller takes.
			let upValue: String
			/// On a route to a place inside a fill of the call, the name the caller's tree binds the struct its own member for the
			/// call's case returns under, by the name a fill takes the struct of its level under.
			let carriedStructs: [String: String]
		}

		/// The enclosing fill or dispatcher a call passes by name, whatever expression passes it: its key and its name.
		struct EnclosingFill: Sendable {
			let key: String
			let name: String
		}

		let label: String
		let value: String
		/// The enclosing fill or dispatcher passed by name, or `nil` when the call declares it or passes a builder up.
		let enclosingFill: EnclosingFill?
		/// Whether the seam takes the builder `@Sendable`.
		let isSendable: Bool
		/// For a builder of a public mock that takes a builder struct, what the call passes in place of `value`.
		let builderStruct: PublicMockBuilderStruct?
		/// For a builder of another module's public mock, what an override closure of the call can be handed for it.
		let overrideHanding: OverrideHanding
	}

	/// A level of a seam's or a public mock's tree a caller generates a function for, which returns the level's builder
	/// struct: each member hands its case to the fill of its place or the function of the level it leads to. A cycle of
	/// levels is ordinary mutual recursion. A public mock's caller declares its level functions through
	/// `PublicMockLevelFunctions`, which fills some places of a level and passes the others up.
	///
	/// Over an enum nested by type, a case carries what its type binds before the case's property, and the fill or
	/// dispatcher it hands its value to may read a value a type further out binds: that one takes it as a parameter, which
	/// each case that leads to it passes from its own payload, or, where its payload does not hold it, from the dispatcher's
	/// own parameter, so the value read is the one the nearest type on the actual route binds, as inline. The root
	/// dispatcher, which the builder is, takes none: a value no type on the route binds is the caller's own declaration of
	/// it, in scope where the dispatchers are declared. The parameters are found when the code is generated, from what the
	/// fills read (`dispatcherParameters(of:fillReads:)`), a fixed point over the enums, which can recurse.
	///
	/// A public mock's caller decides per route (`decidesPerRoute`) when its code is generated: each route hands a fill the
	/// value nearest the place, or the caller's where no level on the route binds one (`PublicMockLevelFunctions`), so
	/// every route of a filled place fills it.
	struct FillDispatcher: Sendable {
		struct Case: Sendable {
			let name: String
			/// Whether a place's case carries a payload struct, which every case does but one of a `@Sendable` enum nested by
			/// type, whose place is held in a `Sendable` wrapper.
			var carriesPayload = true
			let hasForwardedValue: Bool
			/// For a place's case of a level on a carried route, whether the place is held in an instantiator, so the case's member
			/// returns the builder the wrapper keeps over the struct of the fill's level, which takes the forwarded value.
			var returnsWrapperBuilder = false
			/// The fill or dispatcher the case is handed to, or `nil` when every place it reaches is passed up: in a seam's call,
			/// whose dispatcher then hands the case to `passUp`. A call of another module's public mock passes no place up by
			/// route: it declares level functions only for the builders it fills, every place of each (`PublicMockLevelFunctions`).
			let target: Target?
			/// What the case carries before the value it hands on, in an enum nested by type: the fields of its payload.
			var values: [SeamSignature.Hole.Field]?
			/// For a call's case for a builder it fills (`SeamSignature.ScopeEnum.Case.Kind.fill`), whether the case carries the
			/// scope value the inner seam handed the fill, before the value it hands on, and the key of that value's enum, which a
			/// reader reads a value its target takes from (`InnerScopeReaders`).
			var isFillCase = false
			var carriedInnerKey: SeamSignature.ScopeEnum.Key?
			/// The labels the case's type binds from the case's property on, in an enum nested by type, which hide every value
			/// of the label a type further out binds (`SeamSignature.ScopeEnum.Values.labelsBoundLater`).
			let labelsBoundLater: Set<String>

			/// Whether the case's enum is of a seam the called seam calls, which binds the case's deferred parameters from a
			/// call of its own: their memo holds what that call passed, which no declaration of the caller's is.
			var carriesDeferredFields = false

			/// The labels the case hands on from its payload: every field but one bound from a deferred parameter of the
			/// called seam, whose memo inline never reads where the caller's own declaration is in scope.
			var carriedLabels: Set<String> {
				Set((values ?? []).filter { carriesDeferredFields || !$0.isDeferredParameter }.map(\.property.label))
			}

			/// Whether the case hands on, from its payload, `field`, a form a target takes of a label of `carriedLabels`: every
			/// form but, for a deferred parameter's field, which holds the value and its memo, a wrapper a type further out
			/// declares of the label, which a target that reads only that wrapper takes as the place's field
			/// (`ScopeGenerator.fillLabelsReadOnlyAsPlaceField`), handed on from further out, as inline reads that declaration.
			func handsOn(_ field: SeamSignature.Hole.Field) -> Bool {
				guard let carried = values?.first(where: { $0.property.label == field.property.label }), carried.isDeferredParameter else { return true }
				return field.bindsMemo || field.property.asUnwrappedProperty == carried.property.asUnwrappedProperty
			}

			struct Target: Sendable {
				let name: String
				let key: String
				/// Whether the target is a dispatcher that takes `passUp`.
				let takesPassUp: Bool
				/// For a level function an enclosing call declares, which a call inside its fill reuses by name, the structs it
				/// takes (`FillDispatcher.carriedInnerScopes`): this call's level function hands it its own struct of each type
				/// under the reused function's name for it. Empty for every other target.
				var reusedCarriedInnerScopes = [CarriedInnerScope]()
			}
		}

		let key: String
		let functionName: String
		let enumType: TypeDescription
		let returnType: TypeDescription
		let isSendableFamily: Bool
		/// Whether a place the enum reaches is passed up, which the dispatcher hands to `passUp`.
		let takesPassUp: Bool
		var cases: [Case]
		/// Whether the enum is nested in a root enum, so the dispatcher can take what the types further out bind.
		var takesValuesOfOuterTypes = false
		/// The seam whose extension declares the enum.
		var seamType: TypeDescription?
		/// For the dispatcher of a seam's root enum, the name of the scope value it is handed where a fill it leads to takes
		/// that value (`SeamHoles.innerScope(at:innerKey:)`): the dispatcher's parameter is named so, and every dispatcher and
		/// fill it leads to takes the value under it.
		var innerScopeName: String?
		/// Whether the call is of a public mock, whose caller declares a level function per level and per set of values its
		/// routes bind (`PublicMockLevelFunctions`).
		var decidesPerRoute = false
		/// Whether the enum declares a builder struct the dispatcher returns, as one function per level of the seam's tree
		/// (`structDeclaration`), rather than switching over the enum: where the called seam takes the builder struct and no
		/// case of the calling seam carries the scope value the call hands its fills (`SeamHoles.innerScope(at:innerKey:)`),
		/// which its dispatchers, in their enum form, pass on.
		var returnsBuilderStruct = false
		/// For a level function of a seam's builder struct on the route to a place inside a fill of the call, one per hole type
		/// and family of the calling seam whose places the fill holds, in the order of their names
		/// (`SeamHoles.innerScopes(at:innerKey:)`): the name and type of the parameter each fill there takes the struct of its
		/// own level under, and the name the function takes the struct of its level that the caller's member for the call's case
		/// returns under, claimed by the call's allocator apart from every name in scope there. The function hands each level
		/// beneath it, and each fill, what that struct's member returns.
		var carriedInnerScopes = [CarriedInnerScope]()

		struct CarriedInnerScope: Sendable {
			let name: String
			let type: TypeDescription
			let upName: String
		}

		/// The parameters each dispatcher of `dispatchers` takes, by key, labeled and typed as the fields they pass on, in the
		/// order of their labels, given the fields each fill reads that its case's payload may not carry, by the fill's key.
		/// Found as a fixed point: a dispatcher takes each value a case's target reads that the case's payload does not
		/// carry, and a root dispatcher takes none.
		///
		/// A dispatcher takes a label once per form its targets take of it, transitively, so each target is handed the label in
		/// its own form, as the root dispatcher hands it (`ScopeGenerator.FillCallerReads`): two places of one hole type, one
		/// beneath a type that binds the label lazily and one beneath a type that binds it by value, each take their own form
		/// of a level that binds none above them. An optional form whose unwrapped form a target takes too is taken as that
		/// form, since every route that reaches such a target hands it a value that is no optional. Nothing is chosen among
		/// forms, so none depends on the order the enums are met in. A form some target takes as a deferred parameter's memo
		/// (`Field.bindsMemo`) is taken as the memo (`handsForm(_:inPlaceOf:)`), which the dispatcher hands a target that takes
		/// the value as its instance (`structDeclaration`). Two forms of one label are named apart (`parameterNames(of:)`).
		static func dispatcherParameters(of dispatchers: [FillDispatcher], fillReads: [String: [SeamSignature.Hole.Field]]) -> [String: [SeamSignature.Hole.Field]] {
			var formsByLabelByKey = [String: [String: [Property: SeamSignature.Hole.Field]]]()
			for (key, fields) in fillReads {
				for field in fields {
					formsByLabelByKey[key, default: [:]][field.property.label, default: [:]][field.property] = field
				}
			}
			var changed = true
			while changed {
				changed = false
				for dispatcher in dispatchers where dispatcher.takesValuesOfOuterTypes {
					for dispatcherCase in dispatcher.cases {
						guard let target = dispatcherCase.target else { continue }
						let carried = dispatcherCase.carriedLabels
						for (label, forms) in formsByLabelByKey[target.key, default: [:]] {
							for (property, field) in forms where !carried.contains(label) || !dispatcherCase.handsOn(field) {
								guard Self.handsForm(field, inPlaceOf: formsByLabelByKey[dispatcher.key]?[label]?[property]) else { continue }
								formsByLabelByKey[dispatcher.key, default: [:]][label, default: [:]][property] = field
								changed = true
							}
						}
					}
				}
			}
			var parametersByKey = [String: [SeamSignature.Hole.Field]]()
			for dispatcher in dispatchers where dispatcher.takesValuesOfOuterTypes {
				guard let formsByLabel = formsByLabelByKey[dispatcher.key] else { continue }
				parametersByKey[dispatcher.key] = formsByLabel.keys.sorted().flatMap { label in
					let forms = formsByLabel[label, default: [:]]
					return forms.keys.sorted().compactMap { property in
						Self.unwrappedForm(of: property, among: forms) == nil ? forms[property] : nil
					}
				}
			}
			return parametersByKey
		}

		/// The form of `property`'s label among `forms` that a dispatcher takes in its place: the unwrapped form of an optional
		/// `property`, where `forms` holds it, else `nil`.
		private static func unwrappedForm(of property: Property, among forms: [Property: some Any]) -> Property? {
			guard property.typeDescription.isOptional else { return nil }
			let unwrapped = Property(label: property.label, typeDescription: property.typeDescription.unwrapped)
			return forms[unwrapped] == nil ? nil : unwrapped
		}

		/// The parameter of `parameters`, a dispatcher's, that hands `parameter`, a target's: the one of its form, or of its
		/// unwrapped form, which the dispatcher takes in place of an optional one (`dispatcherParameters(of:fillReads:)`).
		static func parameter(handing parameter: SeamSignature.Hole.Field, among parameters: [SeamSignature.Hole.Field]) -> SeamSignature.Hole.Field? {
			let formsOfLabel = Dictionary(parameters.filter { $0.property.label == parameter.property.label }.map { ($0.property, $0) }) { first, _ in first }
			return formsOfLabel[Self.unwrappedForm(of: parameter.property, among: formsOfLabel) ?? parameter.property]
		}

		/// The name each of `parameters`, a function's, is declared and passed under, by its property: its label, where no
		/// other parameter has that label, else the label and its type (`token_LazilyInstantiated__Token`), with `_` appended
		/// while another parameter has that name.
		static func parameterNames(of parameters: [SeamSignature.Hole.Field]) -> [Property: String] {
			let labelCounts = Dictionary(parameters.map { ($0.property.label, 1) }, uniquingKeysWith: +)
			var names = [Property: String]()
			var usedNames = Set(parameters.map(\.property.label).filter { labelCounts[$0] == 1 })
			for parameter in parameters {
				if labelCounts[parameter.property.label] == 1 {
					names[parameter.property] = parameter.property.label
				} else {
					var name = "\(parameter.property.label)_\(parameter.property.typeDescription.asIdentifier)"
					while usedNames.contains(name) {
						name += "_"
					}
					usedNames.insert(name)
					names[parameter.property] = name
				}
			}
			return names
		}

		/// Whether a dispatcher takes `field`, a form a target takes, in place of `existing`, the field of the same property it
		/// takes so far: a memo in place of the value, and a `SendableLazilyInstantiated` in place of a `LazilyInstantiated`. A
		/// target takes a `SendableLazilyInstantiated` only where every route that hands a memo hands it one, and another route
		/// a value only where its tree reads that wrapper too (`memosHanded(toFillOf:labels:readingSendableWrapper:among:)`), so
		/// a dispatcher on its routes is handed one too, or a value it makes one of, which it hands a target that takes the other
		/// as a memo of its own (`structDeclaration`). The order makes the form independent of the order the targets are met in.
		private static func handsForm(_ field: SeamSignature.Hole.Field, inPlaceOf existing: SeamSignature.Hole.Field?) -> Bool {
			guard let existing else { return true }
			return field.bindsMemo && (!existing.bindsMemo || (field.deferral == .deferred(isSendable: true) && existing.deferral != .deferred(isSendable: true)))
		}

		/// The memo a fill takes of a label some route hands it as the memo of a deferred parameter a level on a carried route
		/// holds (see `memosHanded(toFillOf:labels:readingSendableWrapper:among:)`): the form of that parameter, and its deferral.
		struct HandedMemo: Hashable {
			let property: Property
			let deferral: SeamSignature.Parameter.Deferral
		}

		/// A route that hands a fill the `LazilyInstantiated` memo of a seam's deferred parameter: the seam whose enum's case
		/// carries it, and the type in that seam's tree that receives the parameter, which reads it outside a `@Sendable`
		/// function, with its property and where it receives it.
		struct PlainMemoRoute: Hashable, Sendable {
			let seamType: TypeDescription
			let receivingType: TypeDescription
			let receivedProperty: Property
			let receivedAt: Dependency.DeclarationLocation?
		}

		/// What `memosHanded(toFillOf:labels:readingSendableWrapper:among:)` finds: the memo the fill takes of each label, and,
		/// for each label it takes a `LazilyInstantiated` of while its tree reads the label as a `SendableLazilyInstantiated`
		/// of the memo's form too, the routes that hand a seam's `LazilyInstantiated`, in the order of their seams' names, then
		/// where each receives the value.
		struct HandedMemos {
			var memoByLabel = [String: HandedMemo]()
			var plainMemoRoutesOfSendableWrapperReads = [String: [PlainMemoRoute]]()
			/// By each label of `memoByLabel`, the deferred parameters whose memos the routes hand, in the order the routes are
			/// met: which seam's error validation reports first is decided by where the seam is declared.
			var memoOriginsByLabel = [String: [SeamSignature.Hole.Field.SeamParameterOrigin]]()
		}

		/// What the routes to a fill or dispatcher hand of one label: the memos of deferred parameters levels on carried routes
		/// hold, the routes among them that hand a `LazilyInstantiated`, and whether a route hands the value instead.
		private struct HandedForms: Equatable {
			var memos = Set<HandedMemo>()
			var plainMemoRoutes = Set<PlainMemoRoute>()
			/// The seams whose deferred parameters the memos are, in the order the routes are first met, which only grows.
			var memoSeamTypes = [TypeDescription]()
			var handsValue = false

			mutating func formUnion(_ other: HandedForms) {
				memos.formUnion(other.memos)
				plainMemoRoutes.formUnion(other.plainMemoRoutes)
				memoSeamTypes += other.memoSeamTypes.filter { !memoSeamTypes.contains($0) }
				handsValue = handsValue || other.handsValue
			}
		}

		/// The memo the fill of `fillKey` takes, by each label among `labels` some route of `dispatchers` hands it as a memo: on
		/// a route, the nearest case that carries the label hands the memo where it is a case of a level on a carried route
		/// (`Case.carriesDeferredFields`) whose field of it is a deferred parameter's, and the value where it carries the label
		/// by value; a route on which no case carries it hands the value too, the caller's declaration, which the root
		/// dispatcher reads. Where every route hands one memo, the fill takes it; where routes hand memos that differ in
		/// deferral or optionality, or a route hands the value, the fill takes a `LazilyInstantiated`, of the optional form
		/// where the memos' forms differ in optionality, which each route makes of what it hands where that is another form
		/// (`structDeclaration`), so the value is created where the fill's tree reads it on every route, as inline. A label no
		/// route hands as a memo is left out, and so is one whose memos differ in more than optionality, which no one memo
		/// type holds: the fill takes the value. Found as a fixed point over the dispatchers, which can recurse: a route that comes back to a dispatcher already
		/// on it hands what that dispatcher's other routes hand.
		///
		/// Where the fill's tree also reads the label as a `SendableLazilyInstantiated` of the memo's form
		/// (`readingSendableWrapper`, by that wrapper's instance property) and every route that hands a memo hands that one, the
		/// fill takes it although another route hands the value, which that route makes the memo of: the caller's declaration of
		/// the wrapper itself at the root dispatcher (`FillCallerReads.memoArgumentByMemo`). So the tree reads the wrapper where
		/// it reads the wrapper and its instance where it reads the value, as inline reads one declaration both ways; a
		/// `LazilyInstantiated` it would take instead is no `SendableLazilyInstantiated`. Where a route hands a seam's
		/// `LazilyInstantiated` instead, which no `@Sendable` function can capture, the fill takes a `LazilyInstantiated`, and those
		/// routes are found too (`HandedMemos.plainMemoRoutesOfSendableWrapperReads`), which validation reports.
		static func memosHanded(toFillOf fillKey: String, labels: Set<String>, readingSendableWrapper: [String: Property], among dispatchers: [FillDispatcher]) -> HandedMemos {
			var casesByTargetKey = [String: [(dispatcher: FillDispatcher, dispatcherCase: Case)]]()
			for dispatcher in dispatchers {
				for dispatcherCase in dispatcher.cases {
					if let target = dispatcherCase.target {
						casesByTargetKey[target.key, default: []].append((dispatcher, dispatcherCase))
					}
				}
			}
			let keys = [fillKey] + dispatchers.map(\.key)
			var handedMemos = HandedMemos()
			// A seam has one parameter of a label, so its seam names each memo's parameter.
			var memoOriginBySeamType = [TypeDescription: SeamSignature.Hole.Field.SeamParameterOrigin]()
			for label in labels {
				// What the routes to each node hand so far, which only grows.
				var handedByKey = [String: HandedForms]()
				var changed = true
				while changed {
					changed = false
					for key in keys {
						// A node no case leads to is handed nothing this call's dispatchers carry.
						var handed = HandedForms(handsValue: casesByTargetKey[key] == nil)
						for (dispatcher, dispatcherCase) in casesByTargetKey[key] ?? [] {
							if dispatcherCase.carriedLabels.contains(label) {
								if dispatcherCase.carriesDeferredFields, let field = dispatcherCase.values?.first(where: { $0.property.label == label && $0.isDeferredParameter }) {
									handed.memos.insert(HandedMemo(property: field.property, deferral: field.deferral))
									if let origin = field.seamParameterOrigin, !handed.memoSeamTypes.contains(origin.seamType) {
										handed.memoSeamTypes.append(origin.seamType)
										memoOriginBySeamType[origin.seamType] = origin
									}
									if field.deferral == .deferred(isSendable: false), let seamType = dispatcher.seamType {
										handed.plainMemoRoutes.insert(PlainMemoRoute(seamType: seamType, receivingType: field.declaringType, receivedProperty: field.property, receivedAt: field.declarationLocation))
									}
								} else {
									handed.handsValue = true
								}
							} else if dispatcher.takesValuesOfOuterTypes {
								handed.formUnion(handedByKey[dispatcher.key] ?? HandedForms())
							} else {
								// The root dispatcher hands the caller's declaration.
								handed.handsValue = true
							}
						}
						if handedByKey[key] != handed {
							handedByKey[key] = handed
							changed = true
						}
					}
				}
				// Memos whose forms differ only in optionality are taken in the optional form, which each of them provides.
				guard let handed = handedByKey[fillKey],
				      let memo = handed.memos.first,
				      handed.memos.allSatisfy({ $0.property.asUnwrappedProperty == memo.property.asUnwrappedProperty }),
				      let property = handed.memos.allSatisfy({ $0.property == memo.property }) ? memo.property : handed.memos.first(where: { $0.property.typeDescription.isOptional })?.property
				else { continue }
				let takesSendableWrapperReadToo = readingSendableWrapper[label] == memo.property && memo.deferral == .deferred(isSendable: true)
				let takenMemo = handed.memos.count == 1 && (!handed.handsValue || takesSendableWrapperReadToo) ? memo : HandedMemo(property: property, deferral: .deferred(isSendable: false))
				handedMemos.memoByLabel[label] = takenMemo
				handedMemos.memoOriginsByLabel[label] = handed.memoSeamTypes.compactMap { memoOriginBySeamType[$0] }
				if takenMemo.deferral == .deferred(isSendable: false), readingSendableWrapper[label] == takenMemo.property.asUnwrappedProperty, !handed.plainMemoRoutes.isEmpty {
					handedMemos.plainMemoRoutesOfSendableWrapperReads[label] = handed.plainMemoRoutes.sorted { lhs, rhs in
						lhs.seamType.asSource < rhs.seamType.asSource || (lhs.seamType.asSource == rhs.seamType.asSource && [lhs.receivedAt].lexicographicallyPrecedes([rhs.receivedAt], by: Dependency.DeclarationLocation.precedesInSourceOrder))
					}
				}
			}
			return handedMemos
		}

		/// What identifies a dispatcher among the fills and dispatchers enclosing a call.
		/// - Parameter returnsBuilderStruct: Whether the dispatcher is one that returns the enum's builder struct
		///   (`returnsBuilderStruct`), which a call passes by calling it, and which is never one a call that hands the enum's
		///   cases on shares: each is declared apart.
		static func key(of enumKey: SeamSignature.ScopeEnum.Key, returnsBuilderStruct: Bool = false) -> String {
			"dispatcher \(enumKey.spelling)\(returnsBuilderStruct ? " returning its builder struct" : "")"
		}

		/// A dispatcher of an enum, for the routes of one family's root enum, or `nil` for one that serves every route that
		/// reaches the enum (see `dispatchers(of:filledSites:enclosingDispatchers:builderKeysDispatchedOverTheEnum:fillNames:names:innerScopeNameByKey:carriedInnerScopesByKey:decidesPerRoute:)`).
		struct Instance: Hashable {
			let enumKey: SeamSignature.ScopeEnum.Key
			/// Whether the routes are the `@Sendable` root enum's, where the instance serves one family.
			let family: Bool?
			/// Whether the dispatcher returns the enum's builder struct (`FillDispatcher.returnsBuilderStruct`).
			let returnsBuilderStruct: Bool

			/// The key that identifies the dispatcher: the enum's.
			var dispatcherKey: String {
				FillDispatcher.key(of: enumKey, returnsBuilderStruct: returnsBuilderStruct)
			}
		}

		/// The dispatchers a call that passes `calledBuilders` and fills the places of `filledSites` declares, in the order
		/// its arguments first reach them with an explicit stack: one for each enum that reaches a filled place, which no
		/// enclosing call declares.
		///
		/// A public mock's caller passes up a place it does not fill, so a dispatcher that reaches one takes `passUp`. The plain
		/// and the `@Sendable` root enum of a hole type hold the same enums nested by type, but each one's routes reach only its
		/// own places (`CalledBuilders.sitesReachedOnItsRoutes(by:in:)`). A caller fills every place of a hole type of a call or
		/// none (`DependencyTreeGenerator.holesFilled(byCallsOf:in:)`), so an enum both roots reach is filled on both roots'
		/// routes alike, and one dispatcher serves both.
		/// - Parameters:
		///   - enclosingCarriedInnerScopes: The structs each level function of `enclosingDispatchers` takes, by its key.
		///   - decidesPerRoute: Whether the call is of a public mock (see `FillDispatcher.decidesPerRoute`).
		static func dispatchers(
			of calledBuilders: CalledBuilders,
			filledSites: Set<SeamSignature.Hole.Site>,
			enclosingDispatchers: [String: String],
			fillNames: [String: String],
			names: inout GeneratedNameAllocator,
			innerScopeNameByKey: [SeamSignature.ScopeEnum.Key: String] = [:],
			carriedInnerScopesByKey: [SeamSignature.ScopeEnum.Key: [(name: String, type: TypeDescription)]] = [:],
			enclosingCarriedInnerScopes: [String: [CarriedInnerScope]] = [:],
			decidesPerRoute: Bool = false,
		) -> [FillDispatcher] {
			let enumsByKey = calledBuilders.enumsByKey
			let holesBySite = Dictionary(calledBuilders.holes.map { ($0.site, $0) }, uniquingKeysWith: { first, _ in first })
			let builtTypeByHoleType = calledBuilders.holes.builtTypeByHoleType
			let calledSeamTypes = Set(calledBuilders.builders.map(\.enumKey.seamType))
			var sitesReachedByKey = [SeamSignature.ScopeEnum.Key: Set<SeamSignature.Hole.Site>]()
			func sitesReached(from key: SeamSignature.ScopeEnum.Key) -> Set<SeamSignature.Hole.Site> {
				if let sites = sitesReachedByKey[key] {
					return sites
				}
				let sites = SeamSignature.ScopeEnum.sitesReached(from: key, in: enumsByKey)
				sitesReachedByKey[key] = sites
				return sites
			}
			/// The sites the routes of `family`'s root enum reach from the enum of `key`: every site the enum reaches, where the
			/// call is not of a public mock or the dispatcher serves both families.
			func sitesReached(from key: SeamSignature.ScopeEnum.Key, onRoutesOf family: Bool?) -> Set<SeamSignature.Hole.Site> {
				guard decidesPerRoute, let family, let rootKey = rootKey(ofFamily: family, holeType: key.holeType) else { return sitesReached(from: key) }
				return CalledBuilders.sites(sitesReached(from: key), onRoutesOf: rootKey, holeBySite: holesBySite)
			}
			/// The key of the called seam's root enum of `holeType` of `family`.
			func rootKey(ofFamily family: Bool, holeType: SeamSignature.HoleType) -> SeamSignature.ScopeEnum.Key? {
				calledBuilders.builders.first { $0.enumKey.holeType == holeType && $0.enumKey.isSendable == family }?.enumKey
			}
			// The enums a builder the call passes a builder struct for reaches: an enum the call reaches only as the value a case
			// of another seam's enum carries keeps its dispatcher over the enum, which that case's dispatcher hands it.
			var builderStructKeys = Set<SeamSignature.ScopeEnum.Key>()
			var builderStructKeysToVisit = calledBuilders.builders.filter(\.takesBuilderStruct).map(\.enumKey)
			while let key = builderStructKeysToVisit.popLast() {
				guard builderStructKeys.insert(key).inserted else { continue }
				builderStructKeysToVisit += enumsByKey[key]?.cases.compactMap(SeamSignature.ScopeEnum.heldKey(of:)) ?? []
			}
			/// Whether the dispatcher of the enum of `key` returns its builder struct (`FillDispatcher.returnsBuilderStruct`).
			/// An enclosing call that declares its dispatchers over the enum, which this call reuses, keeps it from declaring
			/// any of its own of the hole type. A public mock's caller's dispatchers are the struct's levels by other means
			/// (`PublicMockLevelFunctions`).
			func returnsBuilderStruct(_ key: SeamSignature.ScopeEnum.Key) -> Bool {
				!decidesPerRoute
					&& builderStructKeys.contains(key)
					&& !innerScopeNameByKey.keys.contains { $0.seamType == key.seamType && $0.holeType == key.holeType && carriedInnerScopesByKey[$0] == nil }
					&& !calledBuilders.builders.contains { builder in
						builder.enumKey.holeType == key.holeType && enclosingDispatchers[Self.key(of: builder.enumKey)] != nil
					}
			}
			// The enums each family's routes reach that lead to a filled place, in the order the builders first reach them.
			var reachedKeys = [SeamSignature.ScopeEnum.Key]()
			var familiesByKey = [SeamSignature.ScopeEnum.Key: [Bool]]()
			for builder in calledBuilders.builders {
				let family = builder.enumKey.isSendable
				var visited = Set<SeamSignature.ScopeEnum.Key>()
				var keysToVisit = [builder.enumKey]
				while let key = keysToVisit.popLast() {
					guard !sitesReached(from: key, onRoutesOf: family).isDisjoint(with: filledSites),
					      visited.insert(key).inserted,
					      enclosingDispatchers[Self.key(of: key, returnsBuilderStruct: returnsBuilderStruct(key))] == nil,
					      let scopeEnum = enumsByKey[key]
					else { continue }
					if familiesByKey[key] == nil {
						reachedKeys.append(key)
					}
					if familiesByKey[key]?.contains(family) != true {
						familiesByKey[key, default: []].append(family)
					}
					keysToVisit.append(contentsOf: scopeEnum.cases.reversed().compactMap(SeamSignature.ScopeEnum.heldKey(of:)))
				}
			}
			/// Whether a dispatcher of the enum of `key` for `family`'s routes takes `passUp`.
			func takesPassUp(_ key: SeamSignature.ScopeEnum.Key, onRoutesOf family: Bool?) -> Bool {
				!sitesReached(from: key, onRoutesOf: family).isSubset(of: filledSites)
			}
			/// The instance that dispatches the enum of `key`: one serves every family that reaches the enum, which a caller
			/// fills on every family's routes alike.
			func dispatcherInstance(of key: SeamSignature.ScopeEnum.Key) -> Instance {
				Instance(enumKey: key, family: familiesByKey[key]?.count == 1 ? familiesByKey[key]?.first : nil, returnsBuilderStruct: returnsBuilderStruct(key))
			}
			let instancesToDeclare = reachedKeys.map(dispatcherInstance(of:))
			var dispatcherNames = enclosingDispatchers
			for instance in instancesToDeclare {
				guard let scopeEnum = enumsByKey[instance.enumKey] else { continue }
				// An enum nested by type is named after its own enum too.
				let enumName = scopeEnum.rootTypeName == nil ? "" : "_\(scopeEnum.typeName)"
				dispatcherNames[instance.dispatcherKey] = names.claim(ScopeGenerator.functionName(toBuildPropertyNamed: "\(scopeEnum.builderLabel.spelledWithoutBackticks)_\(DependencyTreeGenerator.seamStem(of: instance.enumKey.seamType))\(enumName)".spelledAsIdentifier))
			}
			// The places a case nested by type stands for are filled by the fill of the first that the builders reach.
			let holeIndexBySite = Dictionary(calledBuilders.holes.enumerated().map { ($0.element.site, $0.offset) }, uniquingKeysWith: { first, _ in first })
			var dispatcherKeys = [String: SeamSignature.ScopeEnum.Key]()
			for instance in instancesToDeclare {
				dispatcherKeys[instance.dispatcherKey] = instance.enumKey
			}
			var dispatchers = instancesToDeclare.compactMap { instance -> FillDispatcher? in
				let key = instance.enumKey
				let family = instance.family
				guard let scopeEnum = enumsByKey[key] else { return nil }
				let cases = scopeEnum.cases.compactMap { enumCase -> Case? in
					switch enumCase.kind {
					case let .place(sites):
						let rootKey = decidesPerRoute ? family.flatMap { rootKey(ofFamily: $0, holeType: key.holeType) } : nil
						let sitesOnRoutes = rootKey.map { CalledBuilders.sites(Set(sites), onRoutesOf: $0, holeBySite: holesBySite) } ?? Set(sites)
						// A dispatcher is declared for an enum only where its routes reach a filled place, and a caller fills every
						// place of a hole type of a call or none, so some site of every place case is filled on the routes it serves.
						guard let site = sites.filter({ filledSites.contains($0) && sitesOnRoutes.contains($0) }).min(by: { holeIndexBySite[$0, default: .max] < holeIndexBySite[$1, default: .max] }), let hole = holesBySite[site] else { return nil }
						let targetKey = ScopeGenerator.fillKey(of: hole)
						return Case(name: enumCase.name, carriesPayload: enumCase.values != nil, hasForwardedValue: hole.forwardedType != nil, target: Case.Target(name: fillNames[targetKey] ?? "", key: targetKey, takesPassUp: false), values: enumCase.values?.fields, labelsBoundLater: enumCase.values?.labelsBoundLater ?? [])
					case let .nested(innerKey, _, _),
					     let .inner(innerKey, _, _),
					     let .fill(_, _, innerKey, _, _):
						// The routes this dispatcher serves reach the places of the enum the case holds that are on them.
						let reachedSites = sitesReached(from: innerKey, onRoutesOf: family)
						let target = dispatcherInstance(of: innerKey)
						var dispatcherCase = Case(name: enumCase.name, hasForwardedValue: false, target: nil, values: enumCase.values?.fields, labelsBoundLater: enumCase.values?.labelsBoundLater ?? [])
						if case .fill = enumCase.kind {
							dispatcherCase.isFillCase = true
							dispatcherCase.carriedInnerKey = SeamSignature.ScopeEnum.carriedInnerKey(of: enumCase)
						}
						guard !reachedSites.isDisjoint(with: filledSites) else { return dispatcherCase }
						let targetKey = target.dispatcherKey
						return Case(
							name: dispatcherCase.name,
							hasForwardedValue: false,
							target: Case.Target(name: dispatcherNames[targetKey] ?? "", key: targetKey, takesPassUp: takesPassUp(innerKey, onRoutesOf: target.family), reusedCarriedInnerScopes: enclosingCarriedInnerScopes[targetKey] ?? []),
							values: dispatcherCase.values,
							isFillCase: dispatcherCase.isFillCase,
							carriedInnerKey: dispatcherCase.carriedInnerKey,
							labelsBoundLater: dispatcherCase.labelsBoundLater,
						)
					}
				}
				let dispatcherKey = instance.dispatcherKey
				// A seam's enum of a seam the called seam calls carries the deferred parameters that call passed.
				let carriesDeferredFields = !decidesPerRoute && !calledSeamTypes.contains(key.seamType)
				var dispatcher = FillDispatcher(
					key: dispatcherKey,
					functionName: dispatcherNames[dispatcherKey] ?? "",
					enumType: scopeEnum.type,
					// The most explicit of the places' spellings, as the called seam's builder spells it (`builtType(of:)`).
					returnType: builtTypeByHoleType[key.holeType] ?? key.holeType.builtType,
					isSendableFamily: key.isSendable,
					takesPassUp: takesPassUp(key, onRoutesOf: family),
					cases: cases.map { dispatcherCase in
						var dispatcherCase = dispatcherCase
						dispatcherCase.carriesDeferredFields = carriesDeferredFields
						return dispatcherCase
					},
				)
				dispatcher.takesValuesOfOuterTypes = key.describedType != nil
				dispatcher.seamType = key.seamType
				dispatcher.innerScopeName = key.describedType == nil ? innerScopeNameByKey[key] : nil
				dispatcher.decidesPerRoute = decidesPerRoute
				dispatcher.returnsBuilderStruct = instance.returnsBuilderStruct
				return dispatcher
			}
			// A seam's case for a builder the call's caller fills with a type whose tree leads to a place returns the called seam's
			// struct over the struct of the fill's own level: a level function for each level of the called seam, and of each seam it
			// passes a place up from, carrying that struct, whose places return the fill's own level's struct.
			// The fill's level each level function of a seam the called seam calls on the way to a fill leads to, by the function's
			// key: where this call's own caller carries a struct to that level, the function carries it too.
			var fillLevelKeyByCarriedDispatcherKey = [String: SeamSignature.ScopeEnum.Key]()
			// A public mock's caller's dispatchers are each a level function that returns the level's struct, as one that returns
			// its builder struct is (`PublicMockLevelFunctions`).
			func returnsLevelStruct(_ dispatcher: FillDispatcher) -> Bool {
				dispatcher.returnsBuilderStruct || decidesPerRoute
			}
			do {
				/// A level of a seam on a carried route, and the fills' levels its places lead to, nearest first: the last is a level
				/// of the called seam's own enums, which the call's dispatchers return; each before it is a level of a seam whose
				/// fill of a deeper seam's place the route passes through, itself carried by the levels after it.
				struct CarriedLevel: Hashable {
					let key: SeamSignature.ScopeEnum.Key
					let fillLevelKeys: [SeamSignature.ScopeEnum.Key]
				}
				func carriedDispatcherKey(of level: CarriedLevel) -> String {
					"\(Self.key(of: level.key, returnsBuilderStruct: true)) carrying \(level.fillLevelKeys.map(\.spelling).joined(separator: " carrying "))"
				}
				var carriedDispatchers = [FillDispatcher]()
				var declaredLevels = Set<CarriedLevel>()
				/// What a level's struct whose places lead to `fillLevelKeys` is generic over: the struct of the nearest fill's level,
				/// over what the levels after it make of the built type.
				func carriedReturnType(of fillLevelKeys: ArraySlice<SeamSignature.ScopeEnum.Key>, builtType: TypeDescription) -> TypeDescription? {
					guard let nearestFillLevelKey = fillLevelKeys.first, let fillLevelEnum = enumsByKey[nearestFillLevelKey] else { return nil }
					let generic = fillLevelKeys.count == 1 ? builtType : carriedReturnType(of: fillLevelKeys.dropFirst(), builtType: builtType)
					return generic.map { .nested(name: ReservedName.builderStructTypeName, parentType: fillLevelEnum.type, generics: [$0]) }
				}
				/// What declaring `level`'s function needs, or `nil` where it declares none.
				func parts(of level: CarriedLevel) -> (nearestFillLevelKey: SeamSignature.ScopeEnum.Key, ownFillLevelKey: SeamSignature.ScopeEnum.Key, fillLevelDispatcher: FillDispatcher, fillLevelEnum: SeamSignature.ScopeEnum, scopeEnum: SeamSignature.ScopeEnum, returnType: TypeDescription)? {
					guard let nearestFillLevelKey = level.fillLevelKeys.first,
					      let ownFillLevelKey = level.fillLevelKeys.last,
					      let fillLevelDispatcher = dispatchers.first(where: { dispatcherKeys[$0.key] == ownFillLevelKey && returnsLevelStruct($0) }),
					      let fillLevelEnum = enumsByKey[nearestFillLevelKey],
					      let scopeEnum = enumsByKey[level.key],
					      let returnType = carriedReturnType(of: level.fillLevelKeys[...], builtType: fillLevelDispatcher.returnType)
					else { return nil }
					return (nearestFillLevelKey, ownFillLevelKey, fillLevelDispatcher, fillLevelEnum, scopeEnum, returnType)
				}
				/// The level a case of `level` leads on to: `nil` for a place's case where the places are the fill's own level's,
				/// and for a fill's case that leads no further.
				func nextLevel(after enumCase: SeamSignature.ScopeEnum.Case, of level: CarriedLevel) -> CarriedLevel? {
					switch enumCase.kind {
					case .place:
						// A place of a seam further out on the route leads to that seam's level, itself carried.
						level.fillLevelKeys.count == 1 ? nil : level.fillLevelKeys.first.map { CarriedLevel(key: $0, fillLevelKeys: Array(level.fillLevelKeys.dropFirst())) }
					case let .nested(heldKey, _, _),
					     let .inner(heldKey, _, _):
						CarriedLevel(key: heldKey, fillLevelKeys: level.fillLevelKeys)
					case let .fill(innerKey, innerEnumType, fillLevelKey, _, _):
						// A fill of a deeper seam's place that leads on: its levels lead to the fill's level, then on as this level does.
						innerEnumType == nil ? nil : CarriedLevel(key: innerKey, fillLevelKeys: [fillLevelKey] + level.fillLevelKeys)
					}
				}
				/// The name of `level`'s function before it is claimed: the builder label of the nearest fill's level, the stems of
				/// that level's seam and `level`'s, and, for a nested enum or where `qualifiesEnum`, the enum's name.
				func unclaimedFunctionName(of level: CarriedLevel, nearestFillLevelKey: SeamSignature.ScopeEnum.Key, fillLevelEnum: SeamSignature.ScopeEnum, scopeEnum: SeamSignature.ScopeEnum, qualifiesEnum: Bool) -> String {
					let enumName = if qualifiesEnum {
						"_" + [scopeEnum.rootTypeName, scopeEnum.typeName].compactMap(\.self).joined(separator: "_")
					} else {
						scopeEnum.rootTypeName == nil ? "" : "_\(scopeEnum.typeName)"
					}
					return "\(fillLevelEnum.builderLabel.spelledWithoutBackticks)_\(DependencyTreeGenerator.seamStem(of: nearestFillLevelKey.seamType))_\(DependencyTreeGenerator.seamStem(of: level.key.seamType))\(enumName)"
				}
				// The levels the cases below lead to, each with the case it carries.
				var carriedFillCases = [(index: Int, caseIndex: Int, level: CarriedLevel)]()
				for index in dispatchers.indices where returnsLevelStruct(dispatchers[index]) {
					guard let enumKey = dispatcherKeys[dispatchers[index].key], let scopeEnum = enumsByKey[enumKey] else { continue }
					for (caseIndex, enumCase) in scopeEnum.cases.enumerated() {
						guard case let .fill(innerKey, _?, fillLevelKey, _, _) = enumCase.kind,
						      caseIndex < dispatchers[index].cases.count,
						      dispatchers[index].cases[caseIndex].target != nil
						else { continue }
						carriedFillCases.append((index, caseIndex, CarriedLevel(key: innerKey, fillLevelKeys: [fillLevelKey])))
					}
				}
				// The enums of the levels that declare a function, by the name each would take: two levels of one builder label and
				// seam pair whose enums are roots, as a seam's plain and `@Sendable` root enums or two root enums under one fill's
				// builder are, would take one name, which the allocator would name apart in the order it meets them, the builder
				// labels' order. Each such level takes its enum's name instead, and none keeps the bare one.
				var enumKeysByUnclaimedFunctionName = [String: Set<SeamSignature.ScopeEnum.Key>]()
				var levelsToReach = carriedFillCases.map(\.level)
				var reachedLevels = Set<CarriedLevel>()
				while let level = levelsToReach.popLast() {
					guard reachedLevels.insert(level).inserted, let levelParts = parts(of: level) else { continue }
					enumKeysByUnclaimedFunctionName[unclaimedFunctionName(of: level, nearestFillLevelKey: levelParts.nearestFillLevelKey, fillLevelEnum: levelParts.fillLevelEnum, scopeEnum: levelParts.scopeEnum, qualifiesEnum: false), default: []].insert(level.key)
					levelsToReach += levelParts.scopeEnum.cases.compactMap { nextLevel(after: $0, of: level) }
				}
				/// The target of a case that leads to `level`, declaring its function and those of the levels beneath it first.
				func carriedTarget(_ level: CarriedLevel) -> Case.Target? {
					guard case let (nearestFillLevelKey, ownFillLevelKey, fillLevelDispatcher, fillLevelEnum, scopeEnum, returnType)? = parts(of: level) else { return nil }
					let key = carriedDispatcherKey(of: level)
					if declaredLevels.insert(level).inserted {
						let unclaimedName = unclaimedFunctionName(of: level, nearestFillLevelKey: nearestFillLevelKey, fillLevelEnum: fillLevelEnum, scopeEnum: scopeEnum, qualifiesEnum: false)
						let qualifiesEnum = enumKeysByUnclaimedFunctionName[unclaimedName, default: []].count > 1
						let functionName = names.claim(ScopeGenerator.functionName(toBuildPropertyNamed: unclaimedFunctionName(of: level, nearestFillLevelKey: nearestFillLevelKey, fillLevelEnum: fillLevelEnum, scopeEnum: scopeEnum, qualifiesEnum: qualifiesEnum).spelledAsIdentifier))
						let index = carriedDispatchers.count
						carriedDispatchers.append(FillDispatcher(
							key: key,
							functionName: functionName,
							enumType: scopeEnum.type,
							returnType: returnType,
							isSendableFamily: level.key.isSendable,
							takesPassUp: false,
							cases: [],
						))
						carriedDispatchers[index].seamType = level.key.seamType
						let cases = scopeEnum.cases.map { enumCase -> Case in
							// Every place of the called seam's builder is filled with the one fulfilling type, whose own level the fill's
							// struct is: the call's, or a seam's further out on the route, itself carried.
							let target: Case.Target? = if case .place = enumCase.kind, level.fillLevelKeys.count == 1 {
								Case.Target(name: fillLevelDispatcher.functionName, key: fillLevelDispatcher.key, takesPassUp: false)
							} else {
								nextLevel(after: enumCase, of: level).flatMap(carriedTarget)
							}
							var dispatcherCase = Case(name: enumCase.name, carriesPayload: enumCase.values != nil, hasForwardedValue: false, target: target, values: enumCase.values?.fields, labelsBoundLater: enumCase.values?.labelsBoundLater ?? [])
							// The called seam's levels are bound by calls the caller's seam makes.
							dispatcherCase.carriesDeferredFields = true
							// A place's site path ends at its property.
							if case let .place(sites) = enumCase.kind {
								dispatcherCase.returnsWrapperBuilder = sites.first?.path.last?.propertyType.isAnyInstantiator ?? false
							}
							return dispatcherCase
						}
						carriedDispatchers[index].cases = cases
						carriedDispatchers[index].takesValuesOfOuterTypes = true
						carriedDispatchers[index].returnsBuilderStruct = true
						fillLevelKeyByCarriedDispatcherKey[key] = ownFillLevelKey
					}
					return Case.Target(name: carriedDispatchers.first { $0.key == key }?.functionName ?? "", key: key, takesPassUp: false)
				}
				for (index, caseIndex, level) in carriedFillCases {
					guard let target = carriedTarget(level) else { continue }
					var carriedCase = Case(
						name: dispatchers[index].cases[caseIndex].name,
						hasForwardedValue: false,
						target: target,
						values: dispatchers[index].cases[caseIndex].values,
						labelsBoundLater: dispatchers[index].cases[caseIndex].labelsBoundLater,
					)
					// The case hands on the memo of a deferred parameter its payload carries, as the case it replaces does: the seam the
					// called seam calls bound it from what its call passed, which no declaration of the caller's is.
					carriedCase.carriesDeferredFields = dispatchers[index].cases[caseIndex].carriesDeferredFields
					dispatchers[index].cases[caseIndex] = carriedCase
				}
				dispatchers += carriedDispatchers
			}
			// The level functions on the route from the called seam's root to a place inside a fill take the struct of their level.
			// A fill that holds places of several hole types or families of the calling seam is handed a struct for each, so its
			// level functions take each under a name of its own, after the fill's parameter it leads to, which names the builder
			// whose route leads there: never a position, which would move to another type when the types are renamed.
			// A level reached from two roots takes the list of the root whose key spells first. Every root here is the called
			// seam's root of a hole type and family, and a level a root reaches has its hole type, so two roots that share a level
			// differ only in family, and the `@Sendable` root's list comes first, whatever the names. That is the list the level
			// needs: the `@Sendable` root reaches it from inside a `@Sendable` function, so each place beneath it is built in one on
			// that route, and a case whose places are built in one on one route and not on another, with a fill that holds a place,
			// is rejected (`placeInsideFillOfCaseOfBothRootEnums`); each fill beneath the level that the list reaches is a fill of a
			// `@Sendable` place, which takes the `@Sendable` family's structs.
			var carriedInnerScopesByLevel = [SeamSignature.ScopeEnum.Key: [(name: String, type: TypeDescription)]]()
			for (rootKey, carried) in carriedInnerScopesByKey.sorted(by: { $0.key.spelling < $1.key.spelling }) {
				var keysToVisit = [rootKey]
				while let key = keysToVisit.popLast() {
					guard carriedInnerScopesByLevel[key] == nil else { continue }
					carriedInnerScopesByLevel[key] = carried
					keysToVisit += enumsByKey[key]?.cases.compactMap(SeamSignature.ScopeEnum.heldKey(of:)) ?? []
				}
			}
			if !carriedInnerScopesByLevel.isEmpty {
				// A level function takes the values its cases' targets read under their labels beside the struct of its level, so
				// that struct's name is claimed apart from every label a carried level's cases hold too, which stay unclaimed: no
				// other name moves for them.
				var labelsOfCarriedLevels = Set<String>()
				for key in carriedInnerScopesByLevel.keys {
					for enumCase in enumsByKey[key]?.cases ?? [] {
						labelsOfCarriedLevels.formUnion((enumCase.values?.fields ?? []).map(\.property.label))
					}
				}
				func claimUpName(_ base: String) -> String {
					var name = base
					while labelsOfCarriedLevels.contains(name) || names.taken.contains(name) {
						name = "\(name)_".spelledAsJoinedIdentifier
					}
					return names.claim(name)
				}
				var upNameByCarriedName = [String: String]()
				var singleUpName: String?
				for (_, carried) in carriedInnerScopesByKey.sorted(by: { $0.key.spelling < $1.key.spelling }) {
					if carried.count == 1 {
						singleUpName = singleUpName ?? claimUpName("up")
					} else {
						for carriedInnerScope in carried where upNameByCarriedName[carriedInnerScope.name] == nil {
							upNameByCarriedName[carriedInnerScope.name] = claimUpName("up_\(carriedInnerScope.name.dropFirst(ReservedName.builderFunctionNamePrefix.count))")
						}
					}
				}
				dispatchers = dispatchers.map { dispatcher in
					var dispatcher = dispatcher
					guard returnsLevelStruct(dispatcher), let key = dispatcherKeys[dispatcher.key] ?? fillLevelKeyByCarriedDispatcherKey[dispatcher.key], let carried = carriedInnerScopesByLevel[key] else { return dispatcher }
					dispatcher.carriedInnerScopes = carried.map { CarriedInnerScope(name: $0.name, type: $0.type, upName: (carried.count == 1 ? singleUpName : upNameByCarriedName[$0.name]) ?? "") }
					// A deeper seam's root on the route takes the struct of its level as a level nested by type does; the called seam's
					// root is handed it by the call.
					if carriedInnerScopesByKey[key] == nil {
						dispatcher.takesValuesOfOuterTypes = true
					}
					return dispatcher
				}
			}
			return dispatchers
		}

		/// The body of a fill generated in the one case of a dispatcher that calls it, in place of a function of its own
		/// (see `ScopeGenerator.inlinableFillKeys`): what the case binds, and the fill's body, indented for the case.
		struct InlinedFill {
			/// Whether the case carries a payload struct, which the fill is handed as its scope.
			let carriesPayload: Bool
			/// Whether the body reads the scope; a case that binds a value it never reads draws a warning.
			let readsScope: Bool
			/// The name the fill's function gives the value an instantiator forwards, or `nil` for a place that forwards none.
			let forwardedValueName: String?
			/// Whether the body reads the forwarded value: a fill never reads a forwarded `Void`.
			let readsForwardedValue: Bool
			let body: [String]
		}

		/// The function of the dispatcher's level, indented by `indent`, `@Sendable` as `isSendable` says, which returns the
		/// level's builder struct (`structDeclaration`). A case whose fill is in `inlinedFills`, by key, holds the fill's body.
		/// - Parameter parametersByKey: What each dispatcher of the call takes beside its enum
		///   (`dispatcherParameters(of:fillReads:)`), and each fill nested by type beside its case's payload, by key.
		func declaration(
			isSendable: Bool,
			indent: String,
			inlinedFills: [String: InlinedFill],
			parametersByKey: [String: [SeamSignature.Hole.Field]] = [:],
			callerArgumentByParameter: [Property: String] = [:],
			callerMemoArgumentByMemo: [Property: String] = [:],
			typesDeclaredEscaping: Set<TypeDescription> = [],
			fillsTakingPayloadFields: Set<String> = [],
			labelsHiddenByReenteringCalls: Set<String> = [],
		) -> String {
			let parameters = parametersByKey[key] ?? []
			let parameterNames = Self.parameterNames(of: parameters)
			// What this function hands on of a value no case carries to a target that takes it as `parameter`: its own parameter
			// of that form (`parameter(handing:among:)`), or, for the root dispatcher, which takes none, the caller's declaration
			// in the form that target takes (`ScopeGenerator.FillCallerReads`), whatever form another target of the call takes it
			// in.
			func ownValue(for parameter: SeamSignature.Hole.Field) -> String {
				takesValuesOfOuterTypes ? parameterNames[parameter.property] ?? parameter.property.label : callerArgumentByParameter[parameter.property] ?? parameter.property.label
			}
			// The names this function binds, apart from the names of what it takes and passes on.
			let labels = Set(parameterNames.values).union(cases.flatMap { dispatcherCase in
				dispatcherCase.target.map { Self.parameterNames(of: parametersByKey[$0.key] ?? []).values.map(\.self) } ?? []
			})
			func name(_ base: String) -> String {
				var name = base
				while labels.contains(name) {
					name += "_"
				}
				return name
			}
			return structDeclaration(
				isSendable: isSendable,
				indent: indent,
				inlinedFills: inlinedFills,
				fillsTakingPayloadFields: fillsTakingPayloadFields,
				parameters: parameters,
				parametersByKey: parametersByKey,
				ownValue: ownValue(for:),
				callerMemoArgument: { callerMemoArgumentByMemo[$0.memoProperty] },
				valuesName: name("values"),
				scopeName: name("scope"),
				typesDeclaredEscaping: typesDeclaredEscaping,
				labelsHiddenByReenteringCalls: labelsHiddenByReenteringCalls,
			)
		}

		/// The function of one level of a seam's tree that returns its enum's builder struct (`returnsBuilderStruct`): it takes
		/// the values the members' targets read that the cases do not carry, as the enum's dispatcher takes them, and returns a
		/// struct whose member for each case calls the function of the next level, handing it what it reads of the values the
		/// member is handed, or holds the fill of the case's place, which reads them. No member's closure captures the values
		/// it is handed: it reads what it needs out of them. A seam's caller fills every place of an enum, so every case has a
		/// target, and no place forwards a value.
		private func structDeclaration(
			isSendable: Bool,
			indent: String,
			inlinedFills: [String: InlinedFill],
			fillsTakingPayloadFields: Set<String>,
			parameters: [SeamSignature.Hole.Field],
			parametersByKey: [String: [SeamSignature.Hole.Field]],
			ownValue: (SeamSignature.Hole.Field) -> String,
			callerMemoArgument: (SeamSignature.Hole.Field) -> String?,
			valuesName: String,
			scopeName: String,
			typesDeclaredEscaping: Set<TypeDescription>,
			labelsHiddenByReenteringCalls: Set<String>,
		) -> String {
			let memberIndent = indent + ScopeGenerator.standardIndent
			/// The argument `target`, the target of `dispatcherCase`, takes for `parameter`, reading the case's payload bound as
			/// `payloadName`, and whether it reads the payload: the struct the caller's member of this level returns for the case,
			/// for the struct of a level on a carried route; else the case's payload's field, or this function's own value.
			func argument(_ parameter: SeamSignature.Hole.Field, named argumentLabel: String, of target: Case.Target, for dispatcherCase: Case, payloadName: String, readsOwnPayload: Bool) -> (text: String, readsPayload: Bool) {
				let label = parameter.property.label
				if let carriedInnerScope = carriedInnerScopes.first(where: { $0.name == label }) {
					// A level function an enclosing call declares takes the struct under its own name for it.
					let argumentLabel = Self.isFill(target) ? label : target.reusedCarriedInnerScopes.first { $0.type == carriedInnerScope.type }?.upName ?? carriedInnerScope.upName
					return ("\(argumentLabel.spelledAsArgumentLabel): \(carriedInnerScope.upName).\(dispatcherCase.name.spelledAsMemberReference)(\(payloadName))", true)
				} else if readsOwnPayload, (dispatcherCase.carriedLabels.contains(label) && dispatcherCase.handsOn(parameter)) || (parameter.bindsMemo && labelsHiddenByReenteringCalls.contains(label) && dispatcherCase.values?.contains { $0.property.label == label } == true), let field = dispatcherCase.values?.first(where: { $0.property.label == label }) {
					// A target that binds a deferred parameter's memo is handed the memo, whose instance it reads where it reads the
					// value: also a deferred field `carriedLabels` leaves out where a call inside a fill passes a fill of this call on
					// beneath another declaration of the label (`fillDeferredLabelsHiddenByReenteringCalls`), which builds the seam
					// again (`Scope.fillUnderConstruction`): the target binds the memo of the seam whose struct it is handed, where the
					// enclosing value is another declaration's. Elsewhere the caller's declaration is the one inline reads, which the
					// branches below hand. The payload is read before the member returns, so no memo made of it captures the payload.
					let source = HandedSource(field, readsMemo: parameter.bindsMemo, expression: "\(payloadName).\(field.memberName(bindingMemo: parameter.bindsMemo))")
					return ("\(argumentLabel.spelledAsArgumentLabel): \(source.handed(to: parameter, capturingExpression: true))", true)
				} else if let ownParameter = Self.parameter(handing: parameter, among: parameters) {
					// This function's own parameter of the target's form: a target of another form is handed its own.
					let source = HandedSource(ownParameter, readsMemo: ownParameter.bindsMemo, expression: ownValue(ownParameter))
					return ("\(argumentLabel.spelledAsArgumentLabel): \(source.handed(to: parameter, capturingExpression: false))", false)
				} else if parameter.bindsMemo, parameter.deferral == .deferred(isSendable: true), let memoArgument = callerMemoArgument(parameter) {
					// The root dispatcher hands a target that takes a `SendableLazilyInstantiated` the caller's declaration of it, or
					// one made of the caller's value (`ScopeGenerator.FillCallerReads.memoArgumentByMemo`).
					return ("\(argumentLabel.spelledAsArgumentLabel): \(memoArgument)", false)
				} else {
					// The root dispatcher hands the caller's declaration, in the form a target that takes the value takes it
					// (`ScopeGenerator.FillCallerReads`).
					let source = HandedSource(expression: ownValue(parameter), type: parameter.property.typeDescription, isMemo: false)
					return ("\(argumentLabel.spelledAsArgumentLabel): \(source.handed(to: parameter, capturingExpression: false))", false)
				}
			}
			/// The parameters of `target`, in the order it declares them: a fill's in their own order; a level function's with
			/// the structs of carried levels first, in the order this function takes them, and the rest in their order; a level
			/// function an enclosing call declares takes only structs, in its own order.
			func orderedCarriedFirst(_ parameters: [SeamSignature.Hole.Field], of target: Case.Target) -> [SeamSignature.Hole.Field] {
				guard !Self.isFill(target), target.reusedCarriedInnerScopes.isEmpty else { return parameters }
				let carriedNames = carriedInnerScopes.map(\.name)
				let carried = carriedNames.compactMap { name in parameters.first { $0.property.label == name } }
				return carried + parameters.filter { !carriedNames.contains($0.property.label) }
			}
			var members = [(name: String, lines: [String])]()
			for (dispatcherCase, target) in cases.compactMap({ dispatcherCase in dispatcherCase.target.map { (dispatcherCase, $0) } }) {
				let targetParameters = parametersByKey[target.key] ?? []
				let targetParameterNames = Self.parameterNames(of: targetParameters)
				if let inlinedFill = inlinedFills[target.key] {
					// The fill's body, which declares no function: a fill that does is called by name, so no function is declared
					// inside the closure the struct stores (`ScopeGenerator.declaresFunction(inFillBody:)`).
					let binding = inlinedFill.carriesPayload && inlinedFill.readsScope ? "scope" : "_"
					members.append((dispatcherCase.name, ["\(dispatcherCase.name.spelledAsArgumentLabel): { \(binding) in"] + inlinedFill.body.map { String($0.dropFirst(memberIndent.count)) } + ["}"]))
				} else if fillsTakingPayloadFields.contains(target.key) || !Self.isFill(target) {
					// A fill that returns a wrapper's builder takes each field of the payload it reads, from the payload, and each
					// value it reads that the payload does not carry, under its label: the builder it returns captures no payload.
					// The next level's function likewise takes what it reads from this case's payload where it carries one.
					let arguments = orderedCarriedFirst(targetParameters, of: target).map { argument($0, named: targetParameterNames[$0.property] ?? $0.property.label, of: target, for: dispatcherCase, payloadName: valuesName, readsOwnPayload: true) }
					let readsValues = arguments.contains(where: \.readsPayload)
					var call = "\(target.name)(\(arguments.map(\.text).joined(separator: ", ")))"
					if dispatcherCase.returnsWrapperBuilder, !Self.isFill(target) {
						// The member of an instantiator's place on a carried route returns the builder the wrapper keeps, which ignores the
						// forwarded value: the fill's level reads it from its own payload. A level that reads the payload is called before
						// the builder is returned, so the builder captures the level's struct, never the payload.
						call = readsValues ? "{ [level = \(call)] _ in level }" : "{ _ in \(call) }"
					}
					members.append((dispatcherCase.name, ["\(dispatcherCase.name.spelledAsArgumentLabel): { \(readsValues ? valuesName : "_") in \(call) }"]))
				} else {
					// A fill nested by type takes the case's payload, and each value it reads that the payload does not carry, under
					// its label: this function's own, or the caller's.
					let bound = dispatcherCase.carriesPayload ? [scopeName] : []
					let arguments = orderedCarriedFirst(targetParameters, of: target).map { argument($0, named: targetParameterNames[$0.property] ?? $0.property.label, of: target, for: dispatcherCase, payloadName: scopeName, readsOwnPayload: false) }
					let readsPayload = !bound.isEmpty || arguments.contains(where: \.readsPayload)
					members.append((dispatcherCase.name, ["\(dispatcherCase.name.spelledAsArgumentLabel): { \(readsPayload ? scopeName : "_") in \(target.name)(\((bound + arguments.map(\.text)).joined(separator: ", "))) }"]))
				}
			}
			// The struct of this level the caller's member returns, on a carried route, before the values the members' targets
			// read.
			var valueParameterList = [String]()
			for carriedInnerScope in carriedInnerScopes where parameters.contains(where: { $0.property.label == carriedInnerScope.name }) || (innerScopeName != nil && cases.contains { dispatcherCase in
				dispatcherCase.target.map { (parametersByKey[$0.key] ?? []).contains { $0.property.label == carriedInnerScope.name } } ?? false
			}) {
				valueParameterList.append("\(carriedInnerScope.upName.spelledAsArgumentLabel): \(TypeDescription.nested(name: ReservedName.builderStructTypeName, parentType: enumType, generics: [Self.carried(carriedInnerScope.type, through: returnType)]).asSource)")
			}
			let carriedNames = Set(carriedInnerScopes.map(\.name))
			let parameterNames = Self.parameterNames(of: parameters)
			valueParameterList += parameters.filter { !carriedNames.contains($0.property.label) }.map { "\((parameterNames[$0.property] ?? $0.property.label).spelledAsArgumentLabel): \($0.boundTypeAsFunctionParameter(amongTypesDeclaredEscaping: typesDeclaredEscaping).asSource)" }
			let valueParameters = valueParameterList.joined(separator: ", ")
			let builderType = TypeDescription.nested(name: ReservedName.builderStructTypeName, parentType: enumType, generics: [returnType])
			var lines = ["\(indent)\(ScopeGenerator.localFunctionPrefix(isSendable: isSendable, isNonisolated: true))func \(functionName)(\(valueParameters)) -> \(builderType.asSource) {"]
			if members.allSatisfy({ $0.lines.count == 1 }) {
				lines.append("\(memberIndent).init(\(members.map { $0.lines[0] }.joined(separator: ", ")))")
			} else if members.count == 1 {
				// One member over several lines opens on the initializer's line and closes the call on its last.
				let memberLines = members[0].lines
				lines.append("\(memberIndent).init(\(memberLines[0])")
				lines += memberLines.dropFirst().dropLast().map { "\(memberIndent)\($0)" }
				lines.append("\(memberIndent)\(memberLines[memberLines.count - 1]))")
			} else {
				// Several members, one of them over several lines: one member per line, each indented once more.
				lines.append("\(memberIndent).init(")
				for (index, member) in members.enumerated() {
					let separator = index == members.count - 1 ? "" : ","
					let memberLines = member.lines
					lines += memberLines.dropLast().map { "\(memberIndent)\(ScopeGenerator.standardIndent)\($0)" }
					lines.append("\(memberIndent)\(ScopeGenerator.standardIndent)\(memberLines[memberLines.count - 1])\(separator)")
				}
				lines.append("\(memberIndent))")
			}
			lines.append("\(indent)}")
			return lines.joined(separator: "\n")
		}

		/// What a level function hands a target of one label: `expression`, of `type`, a deferred parameter's memo where
		/// `isMemo`, else the value, which can be a `LazilyInstantiated` or its `Sendable` twin a type declares.
		struct HandedSource {
			let expression: String
			let type: TypeDescription?
			let isMemo: Bool

			init(expression: String, type: TypeDescription?, isMemo: Bool) {
				self.expression = expression
				self.type = type
				self.isMemo = isMemo
			}

			/// `field` read as `expression`: its memo where `readsMemo` and it is a deferred parameter's, else its value.
			init(_ field: SeamSignature.Hole.Field, readsMemo: Bool, expression: String) {
				let isMemo = readsMemo && field.isDeferredParameter
				self.init(expression: expression, type: isMemo ? field.memoType : field.property.typeDescription, isMemo: isMemo)
			}

			/// The expression `parameter` is handed: the memo's instance where it takes the value, the memo where it takes a memo
			/// of the same type, and else a `LazilyInstantiated` of the parameter's memo type made of what is handed, which reads
			/// the instance of a memo or of a type's `LazilyInstantiated` when its own instance is read, so the value is created
			/// where the target's tree reads it. Where `capturingExpression`, the expression reads the payload, which the closure
			/// of a memo made of it reads first, so it captures no payload.
			func handed(to parameter: SeamSignature.Hole.Field, capturingExpression: Bool) -> String {
				guard parameter.bindsMemo, let memoType = parameter.memoType else {
					return isMemo ? "\(expression).\(Dependency.lazilyInstantiatedInstancePropertyName)" : expression
				}
				guard type != memoType else { return expression }
				let readsInstance = isMemo || type.map { $0.propertyType.isLazilyInstantiated && !$0.isOptional } == true
				let read = readsInstance ? ".\(Dependency.lazilyInstantiatedInstancePropertyName)" : ""
				return capturingExpression
					? "\(memoType.asSource)({ [handed = \(expression)] in handed\(read) })"
					: "\(memoType.asSource)({ \(expression)\(read) })"
			}
		}

		/// The type a level's struct is generic over on a carried route, given `returnType`, what the level's function returns
		/// its struct over: `carriedType`, the caller's struct of the fill's own level, in place of the built type, inside the
		/// structs of the fills' levels a deeper seam's level returns its struct over.
		static func carried(_ carriedType: TypeDescription, through returnType: TypeDescription) -> TypeDescription {
			guard case let .nested(name, parentType, generics) = returnType, name == ReservedName.builderStructTypeName, let built = generics.first, generics.count == 1 else {
				return carriedType
			}
			return .nested(name: name, parentType: parentType, generics: [carried(carriedType, through: built)])
		}

		/// Whether `target` is a fill rather than a dispatcher.
		private static func isFill(_ target: Case.Target) -> Bool {
			!target.key.hasPrefix("dispatcher ")
		}
	}

	/// A builder a seam call passes: the label the seam's generated initializer takes it under, and the function or
	/// builder parameter passed.
	struct HoleCallArgument: Sendable {
		init(label: String, value: String, hole: SeamSignature.Hole, enclosingFillKey: String? = nil) {
			self.label = label
			self.value = value
			self.hole = hole
			self.enclosingFillKey = enclosingFillKey
		}

		let label: String
		let value: String
		/// The called seam's hole the builder is passed for: a site of its own tree, or a site it passes up.
		let hole: SeamSignature.Hole
		/// The key of the enclosing fill passed, when the call is inside a fill of the same site.
		let enclosingFillKey: String?
	}

	/// The fields a site reads where it is built: its scope struct's. A site inside a fill whose case is nested by type
	/// reads its own payload's and those of the cases on its route inside the innermost fill; the cases further out carry
	/// what the seam's tree bound before the call, and the scope value the inner seam handed the fill, which the fill takes
	/// as a parameter, never a field of its struct.
	private static func fieldsCarried(by site: SeamSignature.Hole) -> [SeamSignature.Hole.Field] {
		guard let enumPlace = site.enumPlace, let lastFillStep = enumPlace.route.lastIndex(where: \.leadsIntoFill) else { return site.fields }
		return enumPlace.route[(lastFillStep + 1)...].flatMap { $0.values?.fields ?? [] } + enumPlace.values
	}

	/// What identifies a fill: the site it fills, by the seam whose tree holds the site and the name of the site's scope
	/// struct, never by the seam whose call the fill is declared for, so a call inside the fill of the seam that holds
	/// the site, or of a seam that passes the site's builder up, passes the fill.
	static func fillKey(of hole: SeamSignature.Hole) -> String {
		// A fill's hole is a place of a seam whose builders are shaped, so it has its case nested by type (`enumPlace`),
		// which every place of its type's property shares: the site's path tells the places apart.
		"\(fillCaseKey(of: hole)) \(hole.sitePath.map(\.asSource).joined(separator: " "))"
	}

	/// What identifies the case a fill fills: one fill of a call generates the code of every place of a case nested by type.
	static func fillCaseKey(of hole: SeamSignature.Hole) -> String {
		"\(hole.scopeSeamType.asSource) \(hole.enumPlace.map { $0.enumType(qualifiedBy: nil).asSource } ?? hole.scopeTypeName) \(hole.enumPlace?.caseName ?? "")"
	}

	deinit {
		// A tree of generators can be as deep as the module has types, so the generators this one holds the last
		// references to are released one at a time rather than from within this deinitializer.
		var propertiesToGenerate = [ScopeGenerator]()
		swap(&propertiesToGenerate, &self.propertiesToGenerate)
		DeferredRelease.release(consume propertiesToGenerate)
	}

	// MARK: CustomStringConvertible

	let description: String

	// MARK: Internal

	/// Properties that we require in order to satisfy our (and our children's) dependencies.
	/// Used both to order child generation (dependencies before dependents) and by mock
	/// generation to surface dependencies the tree does not itself provide.
	let receivedProperties: Set<Property>
	/// The properties among `receivedProperties` that only leaves calling another module's public mock receive, each
	/// only if available (see `Scope.publicMockCall`): a mock takes no parameter or override for them.
	let receivedOnlyByPublicMockCalls: Set<Property>
	/// The properties among `receivedOnlyByPublicMockCalls` that some call passes, since the tier it reaches takes them.
	let passedByPublicMockCalls: Set<Property>

	/// The generators of this scope's children, in declaration order, for a walk of a seam's tree that reads what
	/// its generators found. Every generator but the root's is a child of exactly one other.
	nonisolated var children: [ScopeGenerator] {
		propertiesToGenerate
	}

	/// The type this scope builds, or `nil` for an alias.
	nonisolated var builtInstantiable: Instantiable? {
		switch scopeData {
		case let .root(instantiable, _), let .property(instantiable, _, _, _, _, _):
			instantiable
		case .alias, .hole, .fill:
			nil
		}
	}

	/// The property this generator is a site of a hole of, with whether it is `erasedToConcreteExistential`, or `nil`
	/// for every generator that is no site.
	nonisolated var holeSite: (property: Property, erasedToConcreteExistential: Bool)? {
		if case let .hole(property, erasedToConcreteExistential, _) = scopeData {
			(property, erasedToConcreteExistential)
		} else {
			nil
		}
	}

	/// For a hole's generator, the property stack its owner's scope was built with, innermost first: the stack a fill
	/// of the hole builds the property with. Empty for every other generator.
	let ownerPropertyStack: [Property]
	/// The concrete type each entry of `ownerPropertyStack` is built for, beside it. Empty for every generator that is no
	/// hole's.
	let ownerConcreteTypeStack: [TypeDescription]
	/// For a scope in a fill's tree that closes a cycle on a declaration of the filled seam's path, how many declarations of
	/// that path lie beneath the one it closes on: `0` when it closes on the property whose type declares the hole. `nil` for
	/// every other scope, a closer on a declaration inside the fill's own tree among them, and for a closer inside a fill
	/// nested in that fill, whose stack is its own.
	let closedOnFillPathDeclarationsBeneath: Int?

	/// Whether this generator's tree reads `field`, a field of a scope struct, as its fill binds it: it receives the
	/// field, its optional form, or its instance.
	nonisolated func reads(_ field: Property) -> Bool {
		receivedProperties.contains(field)
			|| receivedProperties.contains(field.asOptionalProperty)
			|| field.asLazilyInstantiatedInstancePropertyOfDeclaredBinding.map { receivedProperties.contains($0) || receivedProperties.contains($0.asOptionalProperty) } == true
	}

	/// For a fill, the field it binds from its struct whose memo serves a read of `property`, a `LazilyInstantiated` or
	/// `SendableLazilyInstantiated` in its tree: a field of the label and of the wrapper's instance, bound from a parameter
	/// deferred in a wrapper of the read's own kind, whose memo the fill binds (`bindsMemo`) because its tree reads the value,
	/// so the memo it binds under the label is a wrapper the read takes, of the instance inline holds. A tree that reads only
	/// the wrapper binds no memo. `nil` for every other property, and for a generator that is no fill.
	///
	/// One predicate for validation, which lets such a read through (`DependencyTreeGenerator.validateFills`), and for a
	/// seam's parameters, which then take none for it (`DependencyTreeGenerator.receivers(in:of:instantiables:)`), so the
	/// two cannot disagree.
	nonisolated func fillBoundMemo(servingWrapperRead property: Property) -> SeamSignature.Hole.Field? {
		guard let instance = property.asLazilyInstantiatedInstanceProperty, let built = children.first else { return nil }
		let deferral = SeamSignature.Parameter.Deferral.deferred(isSendable: property.propertyType == .sendableLazilyInstantiated)
		return fillBoundFields.first { field in
			field.property.label == property.label
				&& field.bindsMemo
				&& field.deferral == deferral
				&& field.property.asUnwrappedProperty == instance.asUnwrappedProperty
				&& built.reads(field.property)
		}
	}

	/// The hole this generator is the fill of, or `nil` for every generator that is no fill.
	nonisolated var fillHole: SeamSignature.Hole? {
		if case let .fill(hole, _) = scopeData {
			hole
		} else {
			nil
		}
	}

	/// Whether this generator closes a property cycle: it refers to an enclosing builder function and builds nothing.
	nonisolated var closesPropertyCycle: Bool {
		if case let .property(_, _, _, _, isPropertyCycle, _) = scopeData {
			isPropertyCycle
		} else {
			false
		}
	}

	/// The parameters of the seam initializer this scope calls, or `nil` for a scope that builds its type.
	nonisolated var seamCallParameters: [SeamSignature.Parameter]? {
		if case let .property(_, _, _, _, _, seamCall?) = scopeData {
			seamCall.parameters
		} else {
			nil
		}
	}

	/// The seam call this scope makes, or `nil` for a scope that builds its type.
	nonisolated var seamCall: SeamCall? {
		if case let .property(_, _, _, _, _, seamCall) = scopeData {
			seamCall
		} else {
			nil
		}
	}

	/// The builders this scope's call of another module's seam or public mock passes, or `nil` for a scope that builds its
	/// type.
	nonisolated var calledBuilders: CalledBuilders? {
		seamCall?.calledBuilders ?? publicMockCall?.calledBuilders
	}

	/// The enclosing fills this scope's seam call passes on, in builder-label order, each by its key (see `fillKey(of:)`)
	/// with the called seam's hole it is passed for: the call is inside each, of a seam that holds the fill's site or
	/// passes its builder up, so it re-enters the fill. Empty for every other scope.
	nonisolated var enclosingFillsPassed: [(key: String, calledHole: SeamSignature.Hole)] {
		holeCallArguments.compactMap { holeCallArgument in
			holeCallArgument.enclosingFillKey.map { ($0, holeCallArgument.hole) }
		}
	}

	/// The properties this scope provides to the scopes beneath it, which then do not receive them from the scopes
	/// enclosing it: those it declares, with the instance of each lazily instantiated one, and those its type is
	/// forwarded, with their instances.
	nonisolated var providedProperties: Set<Property> {
		propertiesToDeclare.union(builtInstantiable?.forwardedReceivableProperties ?? [])
	}

	/// Whether a scope that declares `declaredProperties` and forwards `forwardedProperties` provides
	/// `property` to the scopes beneath it, which then do not receive it from the scope's ancestors:
	/// the scope declares or forwards the property itself or, for an optional property, its unwrapped
	/// form (a declared form handles a non-optional version promoted to satisfy both required and
	/// onlyIfAvailable receivers; a forwarded `x: X` fulfills an `x: X?` beneath it). A scope declares a
	/// lazily instantiated property together with the property that receives its instance by value,
	/// and forwards it together with that property too. A mock's promotion asks it of the mocked type's
	/// own aliases, which the mock binds at its root, beside the dependencies it promotes.
	nonisolated static func provides(
		_ property: Property,
		declaredProperties: Set<Property>,
		forwardedProperties: Set<Property>,
	) -> Bool {
		// Every scope of every tree asks this of each property its children receive, and most scopes forward nothing.
		(!declaredProperties.isEmpty && declaredProperties.contains(property))
			|| (!forwardedProperties.isEmpty && forwardedProperties.contains(property))
			|| (property.typeDescription.isOptional
				&& ((!declaredProperties.isEmpty && declaredProperties.contains(property.asUnwrappedProperty))
					|| (!forwardedProperties.isEmpty && forwardedProperties.contains(property.asUnwrappedProperty))))
	}

	/// Whether a scope that declares `declaredProperties` and forwards `forwardedProperties` declares the
	/// property an alias of `fulfillingProperty` it declares binds against, which then is not received from
	/// the scope's ancestors: the exact property for a required alias, and any form an `onlyIfAvailable`
	/// alias reads (see `Property.formsReadByOnlyIfAvailableReceive`).
	private static func declaresFulfillingProperty(
		of fulfillingProperty: Property,
		onlyIfAvailable: Bool,
		declaredProperties: Set<Property>,
		forwardedProperties: Set<Property>,
	) -> Bool {
		(onlyIfAvailable ? fulfillingProperty.formsReadByOnlyIfAvailableReceive : [fulfillingProperty]).contains {
			declaredProperties.contains($0) || forwardedProperties.contains($0)
		}
	}

	/// The properties `dependencies`, a type's own, declare for the scopes the type builds: those it instantiates and
	/// those it forwards, each lazily instantiated one followed by the property that receives its instance by value. An
	/// alias of one of them is bound inside the type's builder function, and receives nothing from above it.
	private static func propertiesDeclared(byOwnDependencies dependencies: [Dependency]) -> Set<Property> {
		var declaredProperties = Set<Property>()
		for dependency in dependencies {
			switch dependency.source {
			case .instantiated, .forwarded:
				declaredProperties.formUnion(dependency.receivableProperties)
			case .received, .aliased:
				continue
			}
		}
		return declaredProperties
	}

	/// Generates the code of this scope as the root of what is generated, with nothing
	/// generated before it.
	func generateCode(
		codeGeneration: CodeGeneration = .dependencyTree,
	) async throws -> String {
		let code = try await generateCode(
			codeGeneration: codeGeneration,
			unavailableProperties: unavailableProperties(
				isGeneratedBefore: { _ in false },
				propertiesGeneratedLater: [],
			),
			propertiesGeneratedLater: [],
			builderFunctionNames: BuilderFunctionNames(),
			leadingWhitespace: "",
			// The root of what is generated is inside no fill an internal mock declares.
			fillPlaceBindings: .none,
		)
		// The tree's code is spelled once, here: each level holds its children's code rather than a copy of its text.
		return code.spelled()
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
	///   - fillPlaceBindings: The bindings of the places inside the fills an internal mock declares (`FillPlaceBindings`).
	private func generateCode(
		codeGeneration: CodeGeneration,
		unavailableProperties: Set<Property>,
		propertiesGeneratedLater: Set<Property>,
		builderFunctionNames: BuilderFunctionNames,
		leadingWhitespace: String,
		fillPlaceBindings: FillPlaceBindings,
	) async throws -> GeneratedCode {
		let generatedCode: GeneratedCode
		// Mock code is not cached — the context varies per call site.
		// Dependency tree code is cached by the properties that are unavailable.
		switch codeGeneration {
		case .dependencyTree:
			let cacheKey = UnavailablePropertiesCacheKey(
				unavailableProperties: unavailableProperties,
				propertiesGeneratedLater: propertiesGeneratedLater,
				builderFunctionNames: builderFunctionNames,
				fillPlaceBindings: fillPlaceBindings,
			)
			if let cachedCode = unavailablePropertiesToGeneratedCode[cacheKey] {
				generatedCode = cachedCode
			} else if let generateCodeTask = unavailablePropertiesToGenerateCodeTask[cacheKey] {
				generatedCode = try await generateCodeTask.value
			} else {
				let generateCodeTask = Task {
					let code = try await generatePropertyCode(
						codeGeneration: .dependencyTree,
						unavailableProperties: unavailableProperties,
						propertiesGeneratedLater: propertiesGeneratedLater,
						builderFunctionNames: builderFunctionNames,
						fillPlaceBindings: fillPlaceBindings,
					)
					// A task keeps the memory its async frames took until it is released, so the cache keeps the finished code
					// rather than the task: keeping every finished task held that memory for every scope of the tree until the
					// tree's code was done, about 13 KB for each line generated. The task runs on this actor, so it runs after
					// the line below caches it, and is uncached before anything that asks for the code again can look.
					unavailablePropertiesToGeneratedCode[cacheKey] = code
					unavailablePropertiesToGenerateCodeTask[cacheKey] = nil
					return code
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
				fillPlaceBindings: fillPlaceBindings,
			)
		}
		if leadingWhitespace.isEmpty {
			return generatedCode
		} else {
			// The level holds its scope's code, which the cache shares, and indents it where the tree is spelled.
			return .indented(generatedCode, by: leadingWhitespace)
		}
	}

	/// The code tasks the generators of this scope's tree still hold (see `HeldCodeTasks`). Once the tree's code is
	/// generated, each is a finished task, or one a scope started early for a context nothing asked for, still running.
	/// The tree is walked with a stack, since it can be as deep as the module has types.
	func codeTasksHeldInTree() async -> Int {
		var generators = [self]
		var heldTaskCount = 0
		while let generator = generators.popLast() {
			heldTaskCount += await generator.unavailablePropertiesToGenerateCodeTask.count
			generators += generator.children
		}
		return heldTaskCount
	}

	func generateDOT() async throws -> String {
		// A fill is drawn as the property it fills, which its child builds, so the seam call's edge leads to that
		// property's own edges rather than to an edge from the property to itself.
		if case .fill = scopeData, let child = propertiesToGenerate.first {
			return try await child.generateDOT()
		} else {
			let orderedPropertiesToGenerate = Array(orderedPropertiesToGenerate)
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
	}

	/// A dependency that a type receives inside a `@Sendable` builder function from an `Instantiator`,
	/// `ErasedInstantiator`, or `LazilyInstantiated` declared outside that function. The generated function
	/// would capture the wrapper, which is not `Sendable`.
	struct NonSendableWrapperCapture: Hashable, Sendable {
		/// The property received: the fulfilling property for an aliased dependency, the declared property otherwise.
		let receivedProperty: Property
		/// Where the receiving dependency is declared.
		let declarationLocation: Dependency.DeclarationLocation?
		/// The types from the root of the tree to the receiver, outermost first.
		let chain: [TypeDescription]
		/// The outermost `@Sendable` builder function that encloses the receiver but not the wrapper.
		let sendableBuilder: Property
		/// The type that declares `sendableBuilder`.
		let sendableBuilderDeclaringType: TypeDescription
		/// The seam whose generated initializer takes the received property as a `@Sendable` deferred parameter, when that
		/// parameter is what captures the wrapper, or `nil` when a builder function does.
		let capturingSeamType: TypeDescription?
		/// The seam whose builder for `sendableBuilder` a `@Sendable` fill fills, when that fill is what
		/// captures the wrapper, or `nil` when a builder function does.
		let capturingFillSeamType: TypeDescription?
		/// Whether that fill is `@Sendable` only for where it is passed on: inside a `@Sendable` function that does
		/// not enclose it, or to a seam that takes it `@Sendable`. No `@Sendable` function of `capturingFillSeamType`'s tree
		/// holds the site then.
		let capturingFillIsPassedOn: Bool
		/// The wrapper property the builder function would capture.
		let wrapperProperty: Property
		/// The type that declares `wrapperProperty`, or `nil` when a mock root's tree receives it
		/// from outside the tree, or when it is a parameter of a builder function a lazy cycle closes on that
		/// the scope declaring the function passes `nil`.
		let wrapperDeclaringType: TypeDescription?
		/// Where `wrapperProperty` is declared, when a type in the tree declares it.
		let wrapperDeclarationLocation: Dependency.DeclarationLocation?
	}

	/// The dependencies in the tree rooted at this scope that a `@Sendable` builder function would capture an
	/// `Instantiator`, `ErasedInstantiator`, or `LazilyInstantiated` declared outside it to pass, in the order
	/// the tree's code is generated.
	///
	/// SafeDI builds a `SendableInstantiator`, `SendableErasedInstantiator`, or `SendableLazilyInstantiated`
	/// in a `@Sendable` function, and passes a dependency by its label, which resolves to the closest
	/// declaration of that label in the generated code: a property an enclosing scope declares or forwards,
	/// or, in a mock, a property the mock root is handed or promotes. This walks the tree as code generation
	/// does, so a dependency passed `nil` captures nothing.
	///
	/// - Parameter instantiable: The type this root scope builds.
	func nonSendableWrapperCaptures(ofTreeRootedAt instantiable: Instantiable) async -> [NonSendableWrapperCapture] {
		// A seam's generated initializer declares its parameters outside every builder function, so a `@Sendable`
		// builder inside the tree that reads a parameter that is a wrapper, or the instance of a non-optional one,
		// captures it, as it captures a declaration of the tree. An optional wrapper parameter offers no instance.
		// A deferred parameter is declared as the `LazilyInstantiated` its body holds it in, whose instance the tree reads.
		// The signature holds a parameter a `@Sendable` function reads in a `SendableLazilyInstantiated`, so this reports
		// nothing unless that decision misses a read, which is then reported here rather than failing to compile.
		var declarationsByLabel = [String: [VisibleDeclaration]]()
		if case let .root(seamInstantiable, seamRoot?) = scopeData {
			let autoclosureCallByLabel = seamRoot.autoclosureCallByLabel(of: seamInstantiable)
			for parameter in seamRoot.signature.parameters {
				let declaration = if case let .deferred(isSendable) = parameter.deferral, autoclosureCallByLabel[parameter.property.label] == nil {
					VisibleDeclaration(
						property: Property(
							label: parameter.property.label,
							typeDescription: .simple(
								name: isSendable ? Dependency.sendableLazilyInstantiatedType : Dependency.lazilyInstantiatedType,
								generics: [parameter.property.typeDescription],
							),
						),
						instanceProperty: parameter.property,
						declaringType: nil,
						declarationLocation: nil,
						sendableBuilderDepth: 0,
					)
				} else {
					VisibleDeclaration(
						property: parameter.property,
						instanceProperty: parameter.property.asLazilyInstantiatedInstancePropertyOfDeclaredBinding,
						declaringType: nil,
						declarationLocation: nil,
						sendableBuilderDepth: 0,
					)
				}
				declarationsByLabel[parameter.property.label, default: []].append(declaration)
			}
		} else {
			// A public mock takes a value its tree receives lazily as the wrapper (`publicMockWrapperParameters(…)`), declared
			// outside every builder function, so a `@Sendable` builder inside the tree that reads its instance by value captures
			// the wrapper, as a seam's tree captures a wrapper parameter. Only such a mock's root reads instances it does not
			// declare (`instancesReadThroughPublicMockWrapperParameters(of:mockDefaults:)`); the wrapper is the one its tree
			// receives of the instance's label and type, of one wrapper kind (`publicMockWrapperParameters(…)`).
			for instanceProperty in lazilyInstantiatedInstanceProperties {
				let wrappers = Set(receivedProperties.lazy.filter { property in
					property.label == instanceProperty.label
						&& property.propertyType.isLazilyInstantiated
						&& property.asValidatedForDependencyCycles.asUnwrappedProperty == instanceProperty.asUnwrappedProperty
				}.map(\.asUnwrappedProperty))
				for wrapper in wrappers {
					declarationsByLabel[instanceProperty.label, default: []].append(VisibleDeclaration(
						property: wrapper,
						instanceProperty: instanceProperty,
						declaringType: nil,
						declarationLocation: nil,
						sendableBuilderDepth: 0,
					))
				}
			}
		}
		return await nonSendableWrapperCaptures(
			of: instantiable,
			unavailableProperties: unavailableProperties(
				isGeneratedBefore: { _ in false },
				propertiesGeneratedLater: [],
			),
			propertiesGeneratedLater: [],
			declarationsByLabel: declarationsByLabel,
			enclosingSendableBuilders: [],
			chain: [],
		)
	}

	/// A value the tree holds for a parameter of a seam's generated initializer that the tier it calls omits, which
	/// the call passes `nil` for although the receivers inside the seam, built inline, would be handed the value.
	struct SeamTierOmission: Sendable {
		/// The seam's leaf: the call.
		let seam: Instantiable
		let seamCall: SeamCall
		/// The parameter the tier omits, or that no tier takes.
		let parameter: SeamSignature.Parameter
		/// Whether no tier of the seam takes the parameter.
		let isNoTierParameter: Bool
		/// The declaration whose binding the call would read built inline: the property it declares, the type that
		/// declares it – `nil` for a parameter of the seam whose tree this is – and where.
		let providerProperty: Property
		let providerDeclaringType: TypeDescription?
		let providerDeclarationLocation: Dependency.DeclarationLocation?
		/// Where the module refers to what leads to the call, as `DependencyTreeGenerator`'s construction check finds it:
		/// the closest dependency on the path to it that a type in one of the module's own files declares, or the
		/// declaration of the tree's root. The error is reported there when the provider's file cannot be read.
		let referenceLocation: Dependency.DeclarationLocation?
		/// When the provider is a pass-through parameter of the seam whose tree this is, the receives in that tree that
		/// make it one, which the error notes beside the omitted parameter's receivers; empty otherwise.
		var providerReceivers = [SeamSignature.Receiver]()
	}

	/// Every value the tree rooted at this scope holds for a parameter a seam tier it calls omits, in the order the tree's
	/// code is generated, followed by those read through a parameter of a builder function a lazy cycle closes on: at
	/// each call of a seam's tier, each parameter the tier omits, or no tier takes, that the call's leaf – which declares
	/// the whole signature, the omitted parameters as receives only if available – would be handed a binding for rather
	/// than `nil`, as generation decides it (`unavailableProperties`), located at the closest declaration of its label. A
	/// seam's own parameters are declarations of the seam's own. Where that declaration is a parameter of a builder
	/// function a lazy cycle closes on, the value is the one each call of the function passes (see `OmissionFindings`).
	/// - Parameters:
	///   - instantiable: The type this root scope builds.
	///   - isOwnFile: Whether a file a declaration records is one of the module's own files.
	func seamTierOmissions(ofTreeRootedAt instantiable: Instantiable, isOwnFile: @escaping @Sendable (String) -> Bool) async -> [SeamTierOmission] {
		var declarationsByLabel = [String: [VisibleDeclaration]]()
		if case let .root(_, seamRoot?) = scopeData {
			for parameter in seamRoot.signature.parameters {
				let ownDependency = instantiable.dependencies.first { $0.property == parameter.property }
				declarationsByLabel[parameter.property.label, default: []].append(VisibleDeclaration(
					property: parameter.property,
					instanceProperty: parameter.property.asLazilyInstantiatedInstancePropertyOfDeclaredBinding,
					declaringType: ownDependency.map { _ in instantiable.concreteInstantiable },
					declarationLocation: ownDependency?.declarationLocation ?? instantiable.declarationLocation,
					sendableBuilderDepth: 0,
				))
			}
		}
		let omissions = await seamTierOmissions(
			of: instantiable,
			propertiesGeneratedLater: [],
			declarationsByLabel: declarationsByLabel,
			enclosingCycleFunctions: [:],
			referenceLocation: instantiable.declarationLocation,
			isOwnFile: isOwnFile,
		).judged()
		guard case let .root(_, seamRoot?) = scopeData else { return omissions }
		// A provider that is a pass-through parameter of this seam is declared by no type: the receives in this seam's
		// tree that make it one say why the seam takes it.
		return omissions.map { omission in
			var omission = omission
			if omission.providerDeclaringType == nil {
				omission.providerReceivers = seamRoot.signature.parameters.first { $0.property == omission.providerProperty }?.receivers ?? []
			}
			return omission
		}
	}

	/// - Parameter enclosingCycleFunctions: The builder functions enclosing this scope that lazy cycles close on and that
	///   take parameters (see `CycleParameter`), by the declaration each builds.
	private func seamTierOmissions(
		of instantiable: Instantiable,
		propertiesGeneratedLater: Set<Property>,
		declarationsByLabel: [String: [VisibleDeclaration]],
		enclosingCycleFunctions: [BuiltDeclaration: ObjectIdentifier],
		referenceLocation: Dependency.DeclarationLocation?,
		isOwnFile: @escaping @Sendable (String) -> Bool,
	) async -> OmissionFindings<SeamTierOmission> {
		let declaringType = instantiable.concreteInstantiable
		var declarationLocationByProperty = [Property: Dependency.DeclarationLocation?]()
		for dependency in instantiable.dependencies where !dependency.source.isReceived {
			declarationLocationByProperty[dependency.property] = dependency.declarationLocation
		}
		// A child's construction is referred to by this type's dependency that builds it when this type is declared in
		// one of the module's own files, and otherwise where this type's construction is.
		let isDeclaredInOwnFile = instantiable.sourceFilePath.map(isOwnFile) ?? false
		func childReferenceLocation(of property: Property?) -> Dependency.DeclarationLocation? {
			guard isDeclaredInOwnFile, let property else { return referenceLocation }
			return declarationLocationByProperty[property].flatMap(\.self) ?? referenceLocation
		}
		func visibleDeclaration(of property: Property, instanceProperty: Property?) -> VisibleDeclaration {
			VisibleDeclaration(
				property: property,
				instanceProperty: instanceProperty,
				declaringType: declaringType,
				declarationLocation: declarationLocationByProperty[property] ?? instantiable.declarationLocation,
				sendableBuilderDepth: 0,
			)
		}
		// Only production trees are walked (`validateNoSeamTierOmitsProvidedValue`), which build every dependency they
		// instantiate, so no scope here has `instantiatedDependenciesNotGenerated`, which `publicMockTierOmissions` enters.
		var scopeDeclarationsByLabel = [String: [VisibleDeclaration]]()
		for dependency in instantiable.dependencies where dependency.source == .forwarded {
			scopeDeclarationsByLabel[dependency.property.label, default: []].append(visibleDeclaration(
				of: dependency.property,
				instanceProperty: dependency.lazilyInstantiatedInstanceProperty,
			))
		}
		let orderedChildren = orderedChildren(propertiesGeneratedLater: propertiesGeneratedLater)
		for child in orderedChildren {
			if let property = child.generator.property {
				scopeDeclarationsByLabel[property.label, default: []].append(visibleDeclaration(
					of: property,
					instanceProperty: child.generator.declaredLazilyInstantiatedInstanceProperty,
				))
			}
		}
		var childDeclarationsByLabel = declarationsByLabel
		childDeclarationsByLabel.merge(scopeDeclarationsByLabel) { _, scopeDeclarations in scopeDeclarations }

		var findings = OmissionFindings<SeamTierOmission>()
		for child in orderedChildren {
			guard case let .property(childInstantiable, _, _, _, isPropertyCycle, seamCall) = child.generator.scopeData else { continue }
			if isPropertyCycle {
				// A scope that closes a cycle constructs nothing: it calls the builder function of the declaration it repeats.
				findings.recordCalls(by: child, of: child.generator.closedOnDeclaration.flatMap { enclosingCycleFunctions[$0] }, among: childDeclarationsByLabel)
			} else if let seamCall {
				let omittedParameters = seamCall.omittedParameters.map { ($0, false) } + seamCall.noTierParameters.map { ($0, true) }
				for (parameter, isNoTierParameter) in omittedParameters {
					// The leaf receives the parameter only if available, as its optional form: generation passes it
					// `nil` exactly when it is among the leaf's unavailable properties.
					guard let leafDependency = childInstantiable.dependencies.first(where: { $0.property.label == parameter.property.label }),
					      !child.unavailableProperties.contains(leafDependency.property)
					else { continue }
					let unwrappedProperty = leafDependency.property.asUnwrappedProperty
					guard let provider = childDeclarationsByLabel[parameter.property.label]?.first(where: { $0.provides(unwrappedProperty) }) else { continue }
					// A function a lazy cycle closes on and every type between it and a scope closing the cycle on it lie in one
					// module, since each builds the next and the last builds the first: the module refers to the call where it
					// refers to the function, whichever call of the function passes the value.
					let referenceLocation = childReferenceLocation(of: child.generator.property)
					findings.append(reading: unwrappedProperty, from: provider) { provider in
						SeamTierOmission(
							seam: childInstantiable,
							seamCall: seamCall,
							parameter: parameter,
							isNoTierParameter: isNoTierParameter,
							providerProperty: provider.property,
							providerDeclaringType: provider.declaringType,
							providerDeclarationLocation: provider.declarationLocation,
							referenceLocation: referenceLocation,
						)
					}
				}
			} else {
				// This scope calls the child's builder function, which, when a lazy cycle closes on it and it takes parameters,
				// it passes them as each cycle-closing scope does. The function's body reads its parameters, which hide every
				// declaration of their labels where it is called, as generation's do.
				let function = ObjectIdentifier(child.generator)
				findings.recordCalls(by: child, of: function, among: childDeclarationsByLabel)
				await findings.append(contentsOf: child.generator.seamTierOmissions(
					of: childInstantiable,
					propertiesGeneratedLater: child.generator.bodyPropertiesGeneratedLater(child.propertiesGeneratedLater),
					declarationsByLabel: child.generator.bodyDeclarations(function: function, enclosing: childDeclarationsByLabel),
					enclosingCycleFunctions: child.generator.bodyEnclosingCycleFunctions(function: function, enclosing: enclosingCycleFunctions),
					referenceLocation: childReferenceLocation(of: child.generator.property),
					isOwnFile: isOwnFile,
				))
			}
		}
		return findings
	}

	/// A value a mock tree holds for a parameter that the tier of a public mock it calls omits, which the call passes
	/// `nil` for although the receivers inside the public mock's tree, built inline, would be handed the value.
	struct PublicMockTierOmission: Sendable {
		/// The leaf that calls the public mock.
		let publicMockCall: PublicMockCall
		/// The parameter the tier omits.
		let parameter: PublicMockParameter
		/// The property the leaf receives for the parameter.
		let receivedProperty: Property
		/// The declaration whose binding the receivers would read built inline: the property it declares, and the type
		/// that declares it, and where.
		let providerProperty: Property
		let providerDeclaringType: TypeDescription
		let providerDeclarationLocation: Dependency.DeclarationLocation?
		/// Whether the provider is a field of the struct the mock of `providerDeclaringType` hands a fill: a value its tree
		/// builds or one its own `mock()` is handed, which the diagnostic names as handed, not as provided by the type.
		let providerIsHandedToFill: Bool
	}

	/// Every value the mock tree rooted at this scope holds for a parameter that a tier of a public mock it calls omits,
	/// in the order the tree's code is generated, followed by those read through a parameter of a builder function a
	/// lazy cycle closes on: at each call, each parameter the tier omits that the call's leaf – which declares the
	/// omitted parameters as receives only if available – would be handed a binding for rather than `nil`, as generation
	/// decides it (`unavailableProperties`), located at the closest declaration of its label. Where that declaration is
	/// a parameter of a builder function a lazy cycle closes on, the value is the one each call of the function passes
	/// (see `OmissionFindings`).
	func publicMockTierOmissions(ofTreeRootedAt instantiable: Instantiable) async -> [PublicMockTierOmission] {
		await publicMockTierOmissions(of: .type(instantiable), propertiesGeneratedLater: [], declarationsByLabel: [:], enclosingCycleFunctions: [:], fillReferenceLocation: nil).judged()
	}

	/// The scope a walk of `publicMockTierOmissions` visits: one that builds a type, or a fill of a builder that a call of
	/// another module's public mock is passed, which builds its place's property and binds the fields of its struct.
	private enum PublicMockTierOmissionScope {
		case type(Instantiable)
		/// A fill passed to the call of `calledType`'s public mock.
		case fill(calledType: TypeDescription)
	}

	/// - Parameters:
	///   - enclosingCycleFunctions: The builder functions enclosing this scope that lazy cycles close on and that take
	///     parameters (see `CycleParameter`), by the declaration each builds.
	///   - fillReferenceLocation: For a scope inside a fill, the dependency in the mock's tree that leads to the call the
	///     outermost fill is passed to, where a value the fill binds, which no declaration in a file states, is located.
	private func publicMockTierOmissions(
		of omissionScope: PublicMockTierOmissionScope,
		propertiesGeneratedLater: Set<Property>,
		declarationsByLabel: [String: [VisibleDeclaration]],
		enclosingCycleFunctions: [BuiltDeclaration: ObjectIdentifier],
		fillReferenceLocation: Dependency.DeclarationLocation??,
	) async -> OmissionFindings<PublicMockTierOmission> {
		let declaringType: TypeDescription
		let dependencies: [Dependency]
		let scopeDeclarationLocation: Dependency.DeclarationLocation?
		switch omissionScope {
		case let .type(instantiable):
			declaringType = instantiable.concreteInstantiable
			dependencies = instantiable.dependencies
			scopeDeclarationLocation = instantiable.declarationLocation
		case let .fill(calledType):
			// The called mock's tree builds what the fill binds, and hands it to the fill through the call.
			declaringType = calledType
			dependencies = []
			scopeDeclarationLocation = fillReferenceLocation.flatMap(\.self)
		}
		var declarationLocationByProperty = [Property: Dependency.DeclarationLocation?]()
		for dependency in dependencies where !dependency.source.isReceived {
			declarationLocationByProperty[dependency.property] = dependency.declarationLocation
		}
		let isFill = switch omissionScope {
		case .type: false
		case .fill: true
		}
		func visibleDeclaration(of property: Property, instanceProperty: Property?) -> VisibleDeclaration {
			var declaration = VisibleDeclaration(
				property: property,
				instanceProperty: instanceProperty,
				// A property a mock root promotes is declared by no type of the tree.
				declaringType: declarationLocationByProperty[property] == nil && !isFill ? nil : declaringType,
				declarationLocation: declarationLocationByProperty[property] ?? scopeDeclarationLocation,
				sendableBuilderDepth: 0,
			)
			declaration.isHandedToFill = isFill
			return declaration
		}
		var scopeDeclarationsByLabel = [String: [VisibleDeclaration]]()
		for dependency in dependencies where dependency.source == .forwarded {
			scopeDeclarationsByLabel[dependency.property.label, default: []].append(visibleDeclaration(
				of: dependency.property,
				instanceProperty: dependency.lazilyInstantiatedInstanceProperty,
			))
		}
		// A dependency the mock cannot build is the value `mock()` is passed for it, bound where this scope is built, which
		// the scopes this scope builds read as they would read the property this scope generated, as
		// `nonSendableWrapperCaptures` judges it.
		for dependency in instantiatedDependenciesNotGenerated {
			scopeDeclarationsByLabel[dependency.property.label, default: []].append(visibleDeclaration(
				of: dependency.property,
				instanceProperty: dependency.lazilyInstantiatedInstanceProperty,
			))
		}
		// A fill binds the fields of its struct, which hide every declaration of their labels where the call is made.
		for field in fillBoundFields {
			scopeDeclarationsByLabel[field.property.label, default: []].append(visibleDeclaration(
				of: field.property,
				instanceProperty: field.property.asLazilyInstantiatedInstancePropertyOfDeclaredBinding,
			))
		}
		let orderedChildren = orderedChildren(propertiesGeneratedLater: propertiesGeneratedLater)
		for child in orderedChildren {
			if let property = child.generator.property {
				scopeDeclarationsByLabel[property.label, default: []].append(visibleDeclaration(
					of: property,
					instanceProperty: child.generator.declaredLazilyInstantiatedInstanceProperty,
				))
			}
		}
		var childDeclarationsByLabel = declarationsByLabel
		childDeclarationsByLabel.merge(scopeDeclarationsByLabel) { _, scopeDeclarations in scopeDeclarations }

		var findings = OmissionFindings<PublicMockTierOmission>()
		for child in orderedChildren {
			guard case let .property(childInstantiable, childProperty, _, _, isPropertyCycle, _) = child.generator.scopeData else { continue }
			if isPropertyCycle {
				// A scope that closes a cycle constructs nothing: it calls the builder function of the declaration it repeats.
				findings.recordCalls(by: child, of: child.generator.closedOnDeclaration.flatMap { enclosingCycleFunctions[$0] }, among: childDeclarationsByLabel)
			} else if let publicMockCall = child.generator.publicMockCall {
				for parameter in publicMockCall.omittedParameters {
					// The leaf receives the parameter only if available, as its optional form: generation would pass it
					// `nil` exactly when it is among the leaf's unavailable properties.
					guard case let .received(property, _) = parameter.role,
					      let leafDependency = childInstantiable.dependencies.first(where: { $0.property.label == property.label }),
					      !child.unavailableProperties.contains(leafDependency.property)
					else { continue }
					let unwrappedProperty = leafDependency.property.asUnwrappedProperty
					guard let provider = childDeclarationsByLabel[property.label]?.first(where: { $0.provides(unwrappedProperty) }) else { continue }
					findings.append(reading: unwrappedProperty, from: provider) { provider in
						PublicMockTierOmission(
							publicMockCall: publicMockCall,
							parameter: parameter,
							receivedProperty: property,
							providerProperty: provider.property,
							// A property the mock root promotes is the mocked type's to provide.
							providerDeclaringType: provider.declaringType ?? declaringType,
							providerDeclarationLocation: provider.declarationLocation,
							providerIsHandedToFill: provider.isHandedToFill,
						)
					}
				}
				// The call's fills are its children, declared in the builder function that makes the call and generated with
				// that function's body's `propertiesGeneratedLater`, as `prepareFillCode(propertiesGeneratedLater:)` generates
				// them. A call a fill makes is led to by the dependency that leads to the call the fill is passed to.
				let callReferenceLocation = fillReferenceLocation ?? .some(declarationLocationByProperty[childProperty].flatMap(\.self) ?? scopeDeclarationLocation)
				let fillsPropertiesGeneratedLater = child.generator.bodyPropertiesGeneratedLater(child.propertiesGeneratedLater)
				for fill in child.generator.orderedChildrenComputedAfresh(propertiesGeneratedLater: fillsPropertiesGeneratedLater) where fill.generator.fillHole != nil {
					await findings.append(contentsOf: fill.generator.publicMockTierOmissions(
						of: .fill(calledType: publicMockCall.type),
						propertiesGeneratedLater: fill.propertiesGeneratedLater,
						declarationsByLabel: childDeclarationsByLabel,
						enclosingCycleFunctions: enclosingCycleFunctions,
						fillReferenceLocation: callReferenceLocation,
					))
				}
			} else {
				// This scope calls the child's builder function, which, when a lazy cycle closes on it and it takes parameters,
				// it passes them as each cycle-closing scope does. The function's body reads its parameters, which hide every
				// declaration of their labels where it is called, as generation's do.
				let function = ObjectIdentifier(child.generator)
				findings.recordCalls(by: child, of: function, among: childDeclarationsByLabel)
				await findings.append(contentsOf: child.generator.publicMockTierOmissions(
					of: .type(childInstantiable),
					propertiesGeneratedLater: child.generator.bodyPropertiesGeneratedLater(child.propertiesGeneratedLater),
					declarationsByLabel: child.generator.bodyDeclarations(function: function, enclosing: childDeclarationsByLabel),
					enclosingCycleFunctions: child.generator.bodyEnclosingCycleFunctions(function: function, enclosing: enclosingCycleFunctions),
					fillReferenceLocation: fillReferenceLocation,
				))
			}
		}
		return findings
	}

	/// Each call in the mock tree rooted at this scope of another module's public mock whose condition the calling
	/// module's mocks do not compile under, with the dependency in the tree that leads to it. A call a fill of a call makes
	/// is led to by the dependency that leads to the call the fill is passed to, where the fill is generated.
	func publicMockCallsUnderOtherMockCondition(ofTreeRootedAt instantiable: Instantiable) async -> [PublicMockCallUnderOtherMockCondition] {
		var calls = [PublicMockCallUnderOtherMockCondition]()
		// Depth first, on a stack of its own, since a mock tree can be as deep as the module has types.
		var scopesToVisit = [(generator: self, instantiable: instantiable, fillReferenceLocation: nil as Dependency.DeclarationLocation??)]
		while let (generator, instantiable, fillReferenceLocation) = scopesToVisit.popLast() {
			for child in generator.propertiesToGenerate {
				switch child.scopeData {
				case let .property(childInstantiable, property, _, _, isPropertyCycle, _):
					guard !isPropertyCycle else { continue }
					let referenceLocation = fillReferenceLocation ?? instantiable.dependencies.first { $0.property.label == property.label }?.declarationLocation ?? instantiable.declarationLocation
					if let publicMockCall = child.publicMockCall {
						if !publicMockCall.mockConditionsAgree {
							calls.append(PublicMockCallUnderOtherMockCondition(publicMockCall: publicMockCall, referenceLocation: referenceLocation))
						}
						// The call's fills are its children.
						for fill in child.propertiesToGenerate {
							scopesToVisit.append((generator: fill, instantiable: childInstantiable, fillReferenceLocation: .some(referenceLocation)))
						}
					} else {
						scopesToVisit.append((generator: child, instantiable: childInstantiable, fillReferenceLocation: fillReferenceLocation))
					}
				case .root, .alias, .hole, .fill:
					continue
				}
			}
		}
		return calls
	}

	/// The calls of other modules' public mocks that the trees of the fills `generator`'s call passes make, each before the
	/// calls of the fills it passes, depth first in the order the fills and their trees are declared.
	static func publicMockCallsInFills(of generator: ScopeGenerator) -> [PublicMockCall] {
		var publicMockCalls = [PublicMockCall]()
		// A stack of its own, since a fill's tree can be as deep as the module has types.
		var generatorsToVisit = Array(generator.propertiesToGenerate.reversed())
		while let generator = generatorsToVisit.popLast() {
			if let publicMockCall = generator.publicMockCall {
				publicMockCalls.append(publicMockCall)
			}
			generatorsToVisit.append(contentsOf: generator.propertiesToGenerate.reversed())
		}
		return publicMockCalls
	}

	/// The concrete type of every scope the tree rooted at this scope builds, this one's excepted.
	func concreteTypesOfTree() async -> Set<TypeDescription> {
		var concreteTypes = Set<TypeDescription>()
		// A stack of its own, since a tree can be as deep as the module has types.
		var generatorsToVisit = [self]
		while let generator = generatorsToVisit.popLast() {
			if case let .property(instantiable, _, _, _, _, _) = generator.scopeData {
				concreteTypes.insert(instantiable.concreteInstantiable)
			}
			generatorsToVisit.append(contentsOf: generator.propertiesToGenerate)
		}
		return concreteTypes
	}

	/// The types the tree rooted at this scope builds that its declarations do not name: through a `fulfilledByType:`
	/// string or a `fulfillingAdditionalTypes:` entry, or as what a mock promotes for such a property, and, in a mock, by
	/// calling a hand-written mock another module merges in. The code generated for the tree names each, while no
	/// declaration of the property does, so no file SafeDI read need import its module.
	/// - Parameter buildingMock: Whether the tree is a mock's, which builds a type with its hand-written mock.
	func fulfillersOfTree(buildingMock: Bool) async -> Set<FulfillerImports.Fulfiller> {
		var fulfillers = Set<FulfillerImports.Fulfiller>()
		// A stack of its own, since a tree can be as deep as the module has types.
		var generatorsToVisit = [self]
		while let generator = generatorsToVisit.popLast() {
			if case let .property(instantiable, property, _, _, _, _) = generator.scopeData {
				let propertyType = property.typeDescription.asInstantiatedType
				fulfillers.formUnion(FulfillerImports.Fulfiller.fulfillers(
					building: instantiable,
					forPropertyOfType: propertyType,
					callingHandWrittenMock: buildingMock && instantiable.mockReturnTypeIsCompatible(withPropertyType: propertyType),
				))
			}
			generatorsToVisit.append(contentsOf: generator.propertiesToGenerate)
		}
		return fulfillers
	}

	/// The types a mock rooted at this scope names that its declarations do not: those its tree builds, those a flat
	/// parameter of `mock()` defaults to, which no scope of the tree builds, and the type it extends, which a mock listed
	/// in `additionalMocksToGenerate` extends from another module.
	/// - Parameter mockDefaults: The hand-written mock a flat parameter of each type defaults to.
	func fulfillersOfMock(mockDefaults: [TypeDescription: FlatParameterMockDefault]) async -> Set<FulfillerImports.Fulfiller> {
		var fulfillers = await fulfillersOfTree(buildingMock: true)
		guard case let .root(instantiable, _) = scopeData else { return fulfillers }
		if let fulfiller = FulfillerImports.Fulfiller(instantiable: instantiable) {
			fulfillers.insert(fulfiller)
		}
		// The parameters are worked out again here only for a default that can need an import, which few mocks have.
		let mockDefaults = mockDefaults.filter { !$0.value.fulfillers.isEmpty }
		guard !mockDefaults.isEmpty else { return fulfillers }
		let parameters = await mockRootParameters(instantiable: instantiable, mockDefaults: mockDefaults)
		for forwardedParameterDefault in parameters.forwardedParameterDefaults.values {
			if case let .handWrittenMock(mockDefault) = forwardedParameterDefault {
				fulfillers.formUnion(mockDefault.fulfillers)
			}
		}
		for mockDefault in parameters.flatReceivedParameterMockDefaults.values {
			fulfillers.formUnion(mockDefault.fulfillers)
		}
		return fulfillers
	}

	// MARK: Private

	/// A property that generated code declares, as `nonSendableWrapperCaptures` sees it.
	private struct VisibleDeclaration {
		let property: Property
		/// The by-value property with which receivers read the instance of `property`, when it is lazily instantiated.
		let instanceProperty: Property?
		/// The type that declares the property, or `nil` for a property a mock root is handed or promotes because
		/// its tree receives it from outside the tree, and for a parameter of a seam's generated initializer, which
		/// the seam's tree receives from outside it too. For a parameter of a builder function a lazy cycle closes on,
		/// the declaration the scope that declares the function passes, if any.
		let declaringType: TypeDescription?
		let declarationLocation: Dependency.DeclarationLocation?
		/// How many `@Sendable` builder functions enclose the declaration.
		let sendableBuilderDepth: Int
		/// For a parameter of a builder function a lazy cycle closes on, as a walk of omissions enters it in the function's
		/// body (see `OmissionFindings`): the function. `nil` for every other declaration.
		var cycleFunction: ObjectIdentifier?
		/// Whether the declaration is a field of the struct a public mock hands a fill of its place, which the fill binds:
		/// `declaringType`'s mock hands it the value, which its tree built or its own `mock()` was handed.
		var isHandedToFill = false

		/// Whether a receive of `unwrappedProperty`, or of its optional form, resolves to this declaration.
		func provides(_ unwrappedProperty: Property) -> Bool {
			property.asUnwrappedProperty == unwrappedProperty || instanceProperty?.asUnwrappedProperty == unwrappedProperty
		}
	}

	/// What a walk finds of the values a tree passes the calls it makes of seams' tiers (`seamTierOmissions`) or of other
	/// modules' public mocks (`publicMockTierOmissions`). A builder function a lazy cycle closes on reads its parameters
	/// (see `CycleParameter`), which the scope that declares it passes as each scope that closes the cycle on it does, so
	/// a call in its body that omits one is judged at the calls of the function, by the declarations they pass, never by
	/// the declarations above the function, as `nonSendableWrapperCaptures` judges a capture of one.
	private struct OmissionFindings<Omission: Sendable>: Sendable {
		/// A call, in the body of a builder function a lazy cycle closes on, that omits a value of one of the function's
		/// parameters: an omission at each declaration a call of the function passes that provides `unwrappedProperty`.
		struct ParameterRead: Sendable {
			let function: ObjectIdentifier
			let label: String
			/// The property the call's leaf receives, unwrapped.
			let unwrappedProperty: Property
			/// The omission, given the declaration that provides the value.
			let omission: @Sendable (VisibleDeclaration) -> Omission
		}

		/// A call of a builder function a lazy cycle closes on that passes its parameter of `label` a value: the
		/// declarations of the label where the call is made.
		struct Call: Sendable {
			let function: ObjectIdentifier
			let label: String
			let declarations: [VisibleDeclaration]
		}

		private(set) var omissions = [Omission]()
		private(set) var parameterReads = [ParameterRead]()
		private(set) var calls = [Call]()

		/// Records the omission of a value of `unwrappedProperty` that `provider`, the declaration the omitting call's leaf
		/// would read, provides.
		mutating func append(reading unwrappedProperty: Property, from provider: VisibleDeclaration, omission: @escaping @Sendable (VisibleDeclaration) -> Omission) {
			if let function = provider.cycleFunction {
				parameterReads.append(ParameterRead(function: function, label: provider.property.label, unwrappedProperty: unwrappedProperty, omission: omission))
			} else {
				omissions.append(omission(provider))
			}
		}

		/// Records the call `child` makes of `function`, which it declares or closes a cycle on, with the declarations of
		/// each parameter's label among `declarationsByLabel`, where the call is made, but for those it passes `nil`.
		/// `function` is `nil` for a function that takes no parameters.
		mutating func recordCalls(by child: OrderedChild, of function: ObjectIdentifier?, among declarationsByLabel: [String: [VisibleDeclaration]]) {
			guard let function else { return }
			for parameter in child.generator.cycleParameters where !child.unavailableProperties.contains(parameter.property) {
				calls.append(Call(function: function, label: parameter.property.label, declarations: declarationsByLabel[parameter.property.label, default: []]))
			}
		}

		mutating func append(contentsOf findings: Self) {
			omissions.append(contentsOf: findings.omissions)
			parameterReads.append(contentsOf: findings.parameterReads)
			calls.append(contentsOf: findings.calls)
		}

		/// The omissions, with each parameter read judged at every call of its function: an omission at each declaration a
		/// call passes that provides what the read receives, or, where a call passes a parameter of an enclosing function,
		/// at the calls of that function in turn.
		func judged() -> [Omission] {
			guard !parameterReads.isEmpty else { return omissions }
			var callsByFunction = [ObjectIdentifier: [Call]]()
			for call in calls {
				callsByFunction[call.function, default: []].append(call)
			}
			var omissions = omissions
			for read in parameterReads {
				var judgedFunctions: Set = [read.function]
				var functionsToJudge = [read.function]
				while let function = functionsToJudge.popLast() {
					for call in callsByFunction[function, default: []] where call.label == read.label {
						guard let provider = call.declarations.first(where: { $0.provides(read.unwrappedProperty) }) else { continue }
						if let enclosingFunction = provider.cycleFunction {
							// A call that passes a function's parameter passes what that function's calls pass.
							if judgedFunctions.insert(enclosingFunction).inserted {
								functionsToJudge.append(enclosingFunction)
							}
						} else {
							omissions.append(read.omission(provider))
						}
					}
				}
			}
			return omissions
		}
	}

	/// A `@Sendable` builder function: the property it builds, and the type that declares that property. For a
	/// seam's `@Sendable` deferred parameter, which a call of the seam's generated initializer hands what it passes,
	/// the property the call builds and the seam (`seamType`).
	private struct SendableBuilder {
		let property: Property
		let declaringType: TypeDescription
		var seamType: TypeDescription?
		/// For a `@Sendable` fill, the seam whose builder for `property` it fills.
		var fillSeamType: TypeDescription?
		/// For such a fill, whether it is `@Sendable` only for where it is passed on.
		var fillIsPassedOn = false
	}

	/// - Parameters:
	///   - instantiable: The type this scope builds. Never a scope that closes a cycle, which constructs nothing:
	///     it refers to an enclosing builder function.
	///   - unavailableProperties: This scope's `unavailableProperties`, as `generateCode` takes them.
	///   - propertiesGeneratedLater: This scope's `propertiesGeneratedLater`, as `generateCode` takes them.
	///   - declarationsByLabel: The declarations each label names where this scope is constructed, all of them
	///     made by the closest scope that declares the label.
	///   - enclosingSendableBuilders: The `@Sendable` builder functions this scope is constructed in, outermost first.
	///   - chain: The types that enclose this scope, outermost first.
	private func nonSendableWrapperCaptures(
		of instantiable: Instantiable,
		unavailableProperties: Set<Property>,
		propertiesGeneratedLater: Set<Property>,
		declarationsByLabel: [String: [VisibleDeclaration]],
		enclosingSendableBuilders: [SendableBuilder],
		chain: [TypeDescription],
	) async -> [NonSendableWrapperCapture] {
		let chain = chain + [instantiable.concreteInstantiable]
		let sendableBuilderDepth = enclosingSendableBuilders.count

		/// The capture a read of `receivedProperty` makes, if any, when the label resolves among `declarationsByLabel`,
		/// inside `enclosingSendableBuilders`, by the receiver at the end of `chain`: by default, a read here.
		func capture(
			of receivedProperty: Property,
			declaredAt declarationLocation: Dependency.DeclarationLocation?,
			among declarationsByLabel: [String: [VisibleDeclaration]],
			inside enclosingSendableBuilders: [SendableBuilder] = enclosingSendableBuilders,
			chain: [TypeDescription] = chain,
		) -> NonSendableWrapperCapture? {
			let sendableBuilderDepth = enclosingSendableBuilders.count
			let wrapperProperty: Property
			let wrapperDeclaration: VisibleDeclaration?
			let capturingBuilder: SendableBuilder
			let unwrappedReceivedProperty = receivedProperty.asUnwrappedProperty
			if let declaration = declarationsByLabel[receivedProperty.label]?.first(where: {
				$0.property.asUnwrappedProperty == unwrappedReceivedProperty || $0.instanceProperty?.asUnwrappedProperty == unwrappedReceivedProperty
			}) {
				guard declaration.property.propertyType.isNonSendableWrapper,
				      declaration.sendableBuilderDepth < sendableBuilderDepth
				else { return nil }
				wrapperProperty = declaration.property
				wrapperDeclaration = declaration
				capturingBuilder = enclosingSendableBuilders[declaration.sendableBuilderDepth]
			} else if receivedProperty.propertyType.isNonSendableWrapper {
				// No declaration in the tree provides the receive, so this is a mock, which declares the property at its
				// root. Production rejects a receive whose label a declaration of another type holds, but a promoted
				// sibling of the mocked type may make one, which `mock()` takes as a parameter or binds from an override at its
				// root.
				wrapperProperty = receivedProperty
				wrapperDeclaration = nil
				capturingBuilder = enclosingSendableBuilders[0]
			} else {
				return nil
			}
			return NonSendableWrapperCapture(
				receivedProperty: receivedProperty,
				declarationLocation: declarationLocation,
				chain: chain,
				sendableBuilder: capturingBuilder.property,
				sendableBuilderDeclaringType: capturingBuilder.declaringType,
				capturingSeamType: capturingBuilder.seamType,
				capturingFillSeamType: capturingBuilder.fillSeamType,
				capturingFillIsPassedOn: capturingBuilder.fillIsPassedOn,
				wrapperProperty: wrapperProperty,
				wrapperDeclaringType: wrapperDeclaration?.declaringType,
				wrapperDeclarationLocation: wrapperDeclaration?.declarationLocation,
			)
		}

		var captures = [NonSendableWrapperCapture]()
		// A call of a seam's generated initializer hands each parameter the seam defers `@Sendable` to a `@Sendable`
		// closure, which captures what the call passes, as a `@Sendable` builder function inside the seam's tree would
		// built inline.
		let sendableDeferredLabels = Set(seamCall?.parameters.filter { $0.deferral == .deferred(isSendable: true) }.map(\.property.label) ?? [])
		// A member of a loop of builders reads what it rebinds inside its own builder function, where it is available, from
		// a wrapper of the declaring scope's function: a read of that declaration, as a cycle argument is.
		let ownUnavailableProperties = reboundProperties.isEmpty ? unavailableProperties : unavailableProperties.subtracting(reboundProperties.flatMap(CycleParameter.forms(providedBy:)))
		for dependency in instantiable.dependencies where dependency.source.isReceived && !ownUnavailableProperties.contains(dependency.property) {
			if let property, sendableDeferredLabels.contains(dependency.property.label) {
				if let capture = capture(
					of: dependency.property,
					declaredAt: dependency.declarationLocation,
					among: declarationsByLabel,
					inside: enclosingSendableBuilders + [SendableBuilder(property: property, declaringType: instantiable.concreteInstantiable, seamType: instantiable.concreteInstantiable)],
				) {
					captures.append(capture)
				}
			} else if sendableBuilderDepth > 0, let capture = capture(of: dependency.property, declaredAt: dependency.declarationLocation, among: declarationsByLabel) {
				// Outside every `@Sendable` builder function, nothing is captured.
				captures.append(capture)
			}
		}

		// The properties this scope declares for the scopes it builds: those it forwards, and its children. A
		// received property a mock root promotes is not among its type's declarations.
		let declaringType = instantiable.concreteInstantiable
		var declarationLocationByProperty = [Property: Dependency.DeclarationLocation?]()
		for dependency in instantiable.dependencies where !dependency.source.isReceived {
			declarationLocationByProperty[dependency.property] = dependency.declarationLocation
		}
		func visibleDeclaration(of property: Property, instanceProperty: Property?) -> VisibleDeclaration {
			if let declarationLocation = declarationLocationByProperty[property] {
				VisibleDeclaration(
					property: property,
					instanceProperty: instanceProperty,
					declaringType: declaringType,
					declarationLocation: declarationLocation,
					sendableBuilderDepth: sendableBuilderDepth,
				)
			} else {
				VisibleDeclaration(
					property: property,
					instanceProperty: instanceProperty,
					declaringType: nil,
					declarationLocation: nil,
					sendableBuilderDepth: sendableBuilderDepth,
				)
			}
		}
		var scopeDeclarationsByLabel = [String: [VisibleDeclaration]]()
		for dependency in instantiable.dependencies where dependency.source == .forwarded {
			scopeDeclarationsByLabel[dependency.property.label, default: []].append(visibleDeclaration(
				of: dependency.property,
				instanceProperty: dependency.lazilyInstantiatedInstanceProperty,
			))
		}
		// A dependency the mock cannot build is the value `mock()` is passed for it, bound where this scope is built, which
		// the scopes this scope builds read as they would read the property this scope generated, as production's does.
		for dependency in instantiatedDependenciesNotGenerated {
			scopeDeclarationsByLabel[dependency.property.label, default: []].append(visibleDeclaration(
				of: dependency.property,
				instanceProperty: dependency.lazilyInstantiatedInstanceProperty,
			))
		}
		let orderedChildren = orderedChildren(propertiesGeneratedLater: propertiesGeneratedLater)
		// An `onlyIfAvailable` alias is declared even where it is bound to `nil`.
		for child in orderedChildren {
			if let property = child.generator.property {
				scopeDeclarationsByLabel[property.label, default: []].append(visibleDeclaration(
					of: property,
					instanceProperty: child.generator.declaredLazilyInstantiatedInstanceProperty,
				))
			}
		}
		var childDeclarationsByLabel = declarationsByLabel
		childDeclarationsByLabel.merge(scopeDeclarationsByLabel) { _, scopeDeclarations in scopeDeclarations }

		/// The captures of a call of the builder function a lazy cycle closes on (see `CycleParameter`) that `child`, which
		/// builds `property`, makes: the scope that declares the function, or one that closes the cycle. The call reads each
		/// argument it does not pass `nil` here, inside `property`'s own `Sendable` wrapper's closure when it has one, for
		/// the function body's first receive of the label.
		func cycleParameterArgumentCaptures(of child: OrderedChild, property: Property) -> [NonSendableWrapperCapture] {
			let callSendableBuilders = property.propertyType.isSendable
				? enclosingSendableBuilders + [SendableBuilder(property: property, declaringType: declaringType)]
				: enclosingSendableBuilders
			// Outside every `@Sendable` function, nothing is captured.
			guard !callSendableBuilders.isEmpty else { return [] }
			var captures = [NonSendableWrapperCapture]()
			for parameter in child.generator.cycleParameters where !child.unavailableProperties.contains(parameter.property) {
				if let capture = capture(
					of: parameter.property,
					declaredAt: parameter.receiver.declarationLocation,
					among: childDeclarationsByLabel,
					inside: callSendableBuilders,
					chain: chain + parameter.receiver.chain,
				) {
					captures.append(capture)
				}
			}
			return captures
		}

		for child in orderedChildren {
			if case let .alias(property, fulfillingProperty, _, onlyIfAvailable, _) = child.generator.scopeData {
				// The alias is bound in this scope's code, where its fulfilling property is read. An alias that keeps
				// its fulfilling property's label is not in scope where that property is read.
				guard sendableBuilderDepth > 0,
				      !Self.aliasIsBoundToNil(onlyIfAvailable: onlyIfAvailable, fulfillingProperty: fulfillingProperty, unavailableProperties: child.unavailableProperties)
				else { continue }
				var fulfillingDeclarationsByLabel = childDeclarationsByLabel
				if fulfillingProperty.label == property.label {
					fulfillingDeclarationsByLabel[property.label] = declarationsByLabel[property.label]
				}
				if let capture = capture(
					of: fulfillingProperty,
					declaredAt: declarationLocationByProperty[property] ?? nil,
					among: fulfillingDeclarationsByLabel,
				) {
					captures.append(capture)
				}
			} else if case let .property(_, childProperty, _, _, isPropertyCycle: true, _) = child.generator.scopeData {
				// A scope that closes a cycle constructs nothing: it refers to an enclosing builder function, which it passes
				// the function's parameters (see `CycleParameter`). Where that function is `@Sendable` because the closer is
				// built inside a `@Sendable` builder function, whatever its kind, the function captures what it reads from
				// above it: SafeDI reports the wrappers among those, as everywhere, and the compiler any other value whose
				// type is not `Sendable`, which SafeDI cannot tell.
				captures.append(contentsOf: cycleParameterArgumentCaptures(of: child, property: childProperty))
			} else if case let .fill(hole, _) = child.generator.scopeData {
				// A fill is declared where the seam is called, and builds the hole's property. It binds the fields it binds from
				// what its builder is handed; its tree reads every other label from the caller's scope – a field bound from a
				// deferred parameter included – as it would inline, so a `@Sendable` function in the fill that reads a wrapper
				// the caller declares captures it.
				await captures.append(contentsOf: fillCaptures(
					of: hole,
					fill: child.generator,
					propertiesGeneratedLater: child.propertiesGeneratedLater,
					isSendable: buildsInSendableFunction(ofFill: child.generator),
					declarationsByLabel: childDeclarationsByLabel,
					enclosingSendableBuilders: enclosingSendableBuilders,
					chain: chain,
				))
			} else if case let .property(childInstantiable, childProperty, _, _, isPropertyCycle: false, _) = child.generator.scopeData {
				let childSendableBuilders = child.generator.buildsInSendableFunction
					? enclosingSendableBuilders + [SendableBuilder(property: childProperty, declaringType: declaringType)]
					: enclosingSendableBuilders
				var bodyDeclarationsByLabel = childDeclarationsByLabel
				if child.generator.declaresCycleParameters {
					// This scope calls the function a lazy cycle closes on as each cycle-closing scope does.
					captures.append(contentsOf: cycleParameterArgumentCaptures(of: child, property: childProperty))
					// The function's body reads each parameter, declared inside the function, and no declaration of its label
					// above it. A `@Sendable` builder function in the body captures the parameter: the error names the
					// declaration this scope passes when it passes one of the parameter's form, and none otherwise, as for a
					// mock root's binding, since what the cycle-closing scopes pass is not known here.
					for parameter in child.generator.cycleParameters {
						let unwrappedProperty = parameter.property.asUnwrappedProperty
						let passedDeclaration = child.unavailableProperties.contains(parameter.property)
							? nil
							: childDeclarationsByLabel[parameter.property.label]?.first { $0.property.asUnwrappedProperty == unwrappedProperty }
						bodyDeclarationsByLabel[parameter.property.label] = [VisibleDeclaration(
							property: passedDeclaration?.property ?? parameter.property,
							instanceProperty: parameter.property.asLazilyInstantiatedInstancePropertyOfDeclaredBinding,
							declaringType: passedDeclaration?.declaringType,
							declarationLocation: passedDeclaration?.declarationLocation,
							sendableBuilderDepth: childSendableBuilders.count,
						)]
					}
				}
				// The parameters hide every declaration of their labels inside the function, whichever is generated later
				// where it is called, as generation's do.
				await captures.append(contentsOf: child.generator.nonSendableWrapperCaptures(
					of: childInstantiable,
					unavailableProperties: child.unavailableProperties,
					propertiesGeneratedLater: child.generator.bodyPropertiesGeneratedLater(child.propertiesGeneratedLater),
					declarationsByLabel: bodyDeclarationsByLabel,
					enclosingSendableBuilders: childSendableBuilders,
					chain: chain,
				))
			}
		}
		return captures
	}

	/// The captures the tree of `fill`, the fill of `hole`, makes (see `nonSendableWrapperCaptures`): its built property's
	/// tree, walked inside the fill's function, `@Sendable` when `isSendable`, beside the fields the fill binds.
	private func fillCaptures(
		of hole: SeamSignature.Hole,
		fill: ScopeGenerator,
		propertiesGeneratedLater: Set<Property>,
		isSendable: Bool,
		declarationsByLabel: [String: [VisibleDeclaration]],
		enclosingSendableBuilders: [SendableBuilder],
		chain: [TypeDescription],
	) async -> [NonSendableWrapperCapture] {
		guard let builtChild = await fill.orderedChildren(propertiesGeneratedLater: propertiesGeneratedLater).first,
		      case let .property(builtInstantiable, builtProperty, _, _, isPropertyCycle: false, _) = builtChild.generator.scopeData
		else { return [] }
		var sendableBuilders = enclosingSendableBuilders
		var fillDeclarationsByLabel = declarationsByLabel
		let boundLabels = fill.fillStructBoundLabels
		if isSendable {
			// Where the place is in no `@Sendable` function of the filled seam's tree, the fill is `@Sendable` only for where it
			// is passed on.
			sendableBuilders.append(SendableBuilder(property: hole.property, declaringType: hole.ownerType, fillSeamType: hole.scopeSeamType, fillIsPassedOn: hole.enumPlace?.isBuiltBySendableBuilder != true))
		}
		for field in hole.fields where boundLabels.contains(field.property.label) {
			fillDeclarationsByLabel[field.property.label] = [VisibleDeclaration(
				property: field.property,
				instanceProperty: field.property.asLazilyInstantiatedInstancePropertyOfDeclaredBinding,
				declaringType: field.declaringType,
				declarationLocation: field.declarationLocation,
				sendableBuilderDepth: sendableBuilders.count,
			)]
		}
		if builtChild.generator.buildsInSendableFunction {
			sendableBuilders.append(SendableBuilder(property: builtProperty, declaringType: hole.ownerType))
		}
		return await builtChild.generator.nonSendableWrapperCaptures(
			of: builtInstantiable,
			unavailableProperties: builtChild.unavailableProperties,
			propertiesGeneratedLater: builtChild.generator.bodyPropertiesGeneratedLater(builtChild.propertiesGeneratedLater),
			declarationsByLabel: fillDeclarationsByLabel,
			enclosingSendableBuilders: sendableBuilders,
			chain: chain,
		)
	}

	private enum ScopeData {
		/// - Parameter seamRoot: What the root emits when it is a seam's, or `nil` for a root of the dependency tree
		///   or a mock root.
		case root(instantiable: Instantiable, seamRoot: SeamRoot?)
		/// - Parameter seamCall: How the scope calls the seam it stands for, or `nil` for a scope that builds its type.
		case property(
			instantiable: Instantiable,
			property: Property,
			forwardedProperties: Set<Property>,
			erasedToConcreteExistential: Bool,
			isPropertyCycle: Bool,
			seamCall: SeamCall?,
		)
		case alias(
			property: Property,
			fulfillingProperty: Property,
			erasedToConcreteExistential: Bool,
			onlyIfAvailable: Bool,
			declarationReference: AliasDeclarationReferences.Reference?,
		)
		/// A site in a seam's tree of a property the builder the seam's generated initializer takes builds. `site` is
		/// `nil` in a tree built only to compute the seam's signature.
		case hole(property: Property, erasedToConcreteExistential: Bool, site: SeamSignature.Hole?)
		/// The function, named `functionName`, a caller of a seam generates to fill the builder for `hole`.
		case fill(hole: SeamSignature.Hole, functionName: String)

		var forwardedProperties: Set<Property> {
			switch self {
			case let .property(_, _, forwardedProperties, _, _, _):
				forwardedProperties
			case .root, .alias, .hole, .fill:
				[]
			}
		}

		var asDOTNode: String {
			switch self {
			case let .root(instantiable, _):
				instantiable.concreteInstantiable.asSource
			case let .property(_, property, _, _, _, _), let .hole(property, _, _):
				"\"\(property.asSource)\""
			case let .alias(property, fulfillingProperty, _, _, _):
				"\"\(property.asSource) <- \(fulfillingProperty.asSource)\""
			case let .fill(hole, _):
				"\"\(hole.property.asSource)\""
			}
		}
	}

	/// What the generator at the root of a seam's tree emits: the seam's generated initializers, one per tier of
	/// `signature`, the narrowest of which builds the tree and calls the seam's own initializer.
	struct SeamRoot: Sendable {
		/// The signature of the generated initializer.
		let signature: SeamSignature
		/// The comment the generated `public` declarations' file carries, naming the types they name that SafeDI reads
		/// no declaration of, or `nil` when the run writes none.
		var unreadTypeComment: UnreadTypeComment?
		/// Whether each tier has a plain initializer for people beside the one generated code calls: set only for a seam
		/// this run generates, from its module's configuration (`SeamResolution.generatesPlainDependencyTreeInitializers`).
		/// No signature, call or guard reads it, so no caller depends on another module's setting.
		var generatesPlainInitializers = false

		/// The call of each deferred parameter's autoclosure that an alias the seam declares, keeping the parameter's
		/// label, is bound from, by label. Such an alias is the parameter's only reader – every declaration beneath it
		/// reads the alias – and is bound where inline binds it, in the generated initializer's body, so the parameter is
		/// read there and held in no `LazilyInstantiated`, which the alias's binding would redeclare.
		func autoclosureCallByLabel(of seam: Instantiable) -> [String: String] {
			var callByLabel = [String: String]()
			for dependency in seam.dependencies {
				guard case let .aliased(fulfillingProperty, _, _) = dependency.source,
				      fulfillingProperty.label == dependency.property.label,
				      let parameter = signature.parameters.first(where: { $0.isDeferred && $0.property.label == fulfillingProperty.label })
				else { continue }
				callByLabel[parameter.property.label] = "\(parameter.internalName)()"
			}
			return callByLabel
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
		/// The hand-written mock a flat parameter of `mock()` of each type defaults to (see `FlatParameterMockDefault`).
		let flatParameterMockDefaults: [TypeDescription: FlatParameterMockDefault]
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
		/// For each concrete type with a hand-written mock, the mock's default-valued parameters. A type's
		/// `SafeDIMockConfiguration` takes its defaults from them (`generateConfigurationStruct`), and a property
		/// built with `init` beneath a pruned edge passes the struct's default for each of them
		/// (`MockParameterNode.callSiteArgumentsForPrunedOverride(handWrittenMockDefaultParameters:)`).
		let handWrittenMockDefaultParameters: [TypeDescription: [MockParameterNode.DefaultParameter]]
		/// The concrete types whose `SafeDIMockConfiguration` is `@Sendable`-typed, from
		/// `collectSendableConfigurationTypeNames` across every root. Such a struct stores each labeled
		/// default-valued parameter as a `@Sendable` closure, which the mock body calls where it builds the type,
		/// so the body must know which structs do (`resolveBuilderArguments`).
		let sendableConfigurationTypeNames: Set<String>
		/// What the module's public mocks share, when the module generates one (`generateMock: .public`).
		let publicMockContext: PublicMockContext?
	}

	private let scopeData: ScopeData
	/// The received properties that some receiver in this subtree requires — a `@Received`
	/// dependency, or the fulfilling property of an aliased one, that is not `onlyIfAvailable`.
	let requiredReceivedProperties: Set<Property>
	/// The unwrapped forms of the optional `requiredReceivedProperties`, which a mock root's promoted sibling of the
	/// non-optional form fulfills: a mock promotes one `x: X` for a required `x: X?` that a forwarded optional fulfills
	/// in production and a required `x: X` elsewhere in its tree. Few receives are both required and optional, so this
	/// stays small.
	private let unwrappedOptionalRequiredReceivedProperties: Set<Property>
	/// Unwrapped versions of the received properties that every receiver in this subtree receives
	/// `@Received(onlyIfAvailable: true)`, directly or through an alias. A property some receiver
	/// requires is excluded: it must be built before this subtree, and a mock must be given it.
	/// Used to order children and by mock generation to identify dependencies that should become
	/// optional mock parameters (no guaranteed default).
	let onlyIfAvailableUnwrappedReceivedProperties: Set<Property>
	/// For an `@Received(onlyIfAvailable: true)` alias whose property no enclosing scope provides,
	/// or only a mock's override of an `onlyIfAvailable` receive does, the alias's fulfilling
	/// property; `nil` for every other scope. The alias is ordered after its fulfilling sibling. A
	/// receiver that requires such an alias can be handed it only if the alias is created, unless
	/// the override is handed to it in the alias's place.
	private let onlyIfAvailableAliasFulfillingProperty: Property?
	/// The `onlyIfAvailable` aliases among this scope's children that a receiver in this scope's
	/// subtree requires. Each is built after its fulfilling property, as a required alias would be.
	private let requiredOnlyIfAvailableAliasProperties: Set<Property>
	/// The fulfilling properties of the `onlyIfAvailable` aliases in this subtree that a receiver
	/// requires, whose label no scope in this subtree declares: the nearest declaration of each is above this
	/// subtree, which is built after it where a scope builds both, although it receives it only if available.
	/// Unlike `requiredReceivedProperties`, these do not make a mock parameter required: a mock binds such an
	/// alias to the optional parameter, and the alias is `nil` where nothing holds its fulfilling property.
	let requiredAliasFulfillingProperties: Set<Property>
	/// The `closedOnDeclaration`s of the cycle-closing scopes in this subtree (see `isPropertyCycle`) whose cycle
	/// closes on a scope enclosing this one. A cycle-closing scope declares no builder function: it
	/// refers by name to the builder function of the enclosing declaration it repeats, so no builder
	/// function declared between the two may share that name (see `builderFunctionNames`).
	private let cycleClosedOnDeclarations: Set<BuiltDeclaration>
	/// Whether a cycle-closing scope in this subtree refers to this scope's builder function.
	private let isReferencedByCycleClosingScope: Bool
	/// This scope's `declaration`, when a cycle-closing scope in this subtree refers to its builder function, or `nil`.
	nonisolated var declarationACycleClosesOn: BuiltDeclaration? {
		isReferencedByCycleClosingScope ? declaration : nil
	}

	/// For a scope that closes a property cycle, the declaration it repeats, whose builder function it calls or hands to
	/// its wrapper: the declaration of its own property, as cycle validation sees both, built for the same concrete type
	/// – the wrapper, where the entry it repeats is a lazily instantiated declaration's instance. A constant and a lazily
	/// instantiated declaration of one label close on each other. Every bookkeeping of the function the cycle closes on
	/// (`cycleClosedOnDeclarations`, `cycleClosingRedeclaredLabels`, `BuilderFunctionNames.enclosingFunctionNames`, the tier
	/// omission passes, `Scope.createScopeGenerator`'s cycle parameter contexts) is keyed by it, and a scope claims the
	/// reference only where its own `declaration` equals it: a declaration of the same property built for another
	/// concrete type between the two is another function, which the closer must not call. `nil` for every other scope.
	nonisolated let closedOnDeclaration: BuiltDeclaration?
	/// The declaration this scope builds – its property, built for its type's concrete type – which a cycle-closing scope
	/// beneath it names as its `closedOnDeclaration` when it repeats it. `nil` for a root, an alias or a hole, which no cycle
	/// closes on.
	nonisolated let declaration: BuiltDeclaration?
	/// The parameters this scope passes the builder function a lazy cycle closes on (see `CycleParameter`): those of its
	/// own function, which it declares, or, for a cycle-closing scope, those of the function it refers to. Empty for
	/// nearly every scope, and for each scope of a tree created once.
	let cycleParameters: [CycleParameter]
	/// Those of `cycleParameters` that are unavailable where this scope passes them, given what the scopes enclosing it
	/// create, before any sibling's ordering is known (see `unavailableProperties(isGeneratedBefore:propertiesGeneratedLater:)`).
	private let cycleParameterUnavailableProperties: Set<Property>
	/// The received properties in scope only as the instance of a `LazilyInstantiated` property where this scope passes
	/// `cycleParameters`: for a scope that declares the function, those its parameters do not hide; for any other scope,
	/// `lazilyInstantiatedInstanceProperties`.
	private let callSiteLazilyInstantiatedInstanceProperties: Set<Property>
	/// For each declaration a cycle-closing scope in this subtree closes on above this scope, the labels the scopes between
	/// it and this scope's parent declare – their instantiated, aliased and forwarded properties and their own builder
	/// functions' parameters (see `CycleParameter`) – each with the declaration of it that comes first in source order.
	/// Empty for nearly every scope.
	let cycleClosingRedeclaredLabels: [BuiltDeclaration: [String: CycleParameter.Redeclaration]]
	/// The parameters this scope's builder function needs, which the next pass of `Scope.createScopeGenerator` creates
	/// the tree with: the labels its tree receives from the scopes enclosing it that a scope between it and one of its
	/// cycle-closing scopes declares (see `CycleParameter.parameters`). Empty for nearly every scope.
	let foundCycleParameters: [CycleParameter]
	/// The labels that the builder functions of the scopes in this tree would need as parameters but that no one
	/// parameter can pass (see `UnpassableCycleLabel`), which `DependencyTreeGenerator` reports. Empty for nearly every
	/// tree.
	let unpassableCycleLabelsInTree: [UnpassableCycleLabel]
	/// Whether a scope in this tree found other parameters for its builder function than it was created with, so that
	/// `Scope.createScopeGenerator` creates the tree again.
	let cycleParametersChangedInTree: Bool
	/// The loops among this scope's children (see `ReceivedBuilderLoops`), which the next pass of
	/// `Scope.createScopeGenerator` creates the children with.
	nonisolated let receivedBuilderLoops: ReceivedBuilderLoops
	/// Whether a scope in this tree found other loops among its children than the pass before, so that
	/// `Scope.createScopeGenerator` creates the tree again.
	let receivedBuilderLoopsChangedInTree: Bool
	/// The loops among this scope's children (keyed as `ReceivedBuilderLoops.loopByChildIndex` keys them) whose members'
	/// payloads and levels this scope's body binds in one box, `__safeDI_<first member's function>_loopLevels`, rather than
	/// in a `let` each, and that each member's function unboxes at its top, each with the name of its box's class
	/// (`LoopLevelsType`), which holds each binding in a stored property of its own.
	/// A member's function names the functions of the members its tree receives, and a local function captures what the
	/// functions it names capture, so in a loop, which is strongly connected, every member's function captured every
	/// member's bindings: the compiled code grew with the square of the loop. Boxed, each captures one reference, which
	/// reaches exactly what the bindings reached, so what the wrappers keep alive is unchanged. Only a loop that binds two
	/// or more is boxed, and none with a `@Sendable` member function, which could not capture the class; the bindings are
	/// those of the loop's own members, bound before its first function, so none holds a wrapper of the loop.
	nonisolated let boxedLoops: [Int: String]
	/// The declaration of each class of `boxedLoops` in this tree, by its name, which the seam whose tree it is declares
	/// beside its initializers.
	let loopLevelsTypesInTree: [String: String]
	/// For a call of another module's public mock, what each level function a call inside one of its fills re-enters takes of
	/// the caller's scope, by its dispatcher's key, where it takes anything (`PublicMockLevelFunctions.levelReentries(amongKeys:)`),
	/// which the next pass of `Scope.createScopeGenerator` hands those calls. Empty for nearly every scope.
	nonisolated let publicMockLevelReentries: [String: PublicMockLevelFunctions.Reentry]
	/// Whether a call in this tree found other `publicMockLevelReentries` than the pass before handed the calls inside its
	/// fills, so that `Scope.createScopeGenerator` creates the tree again.
	let publicMockLevelReentriesChangedInTree: Bool
	/// The properties of the siblings this scope's builder function rebinds, as a member of a loop of its scope (see
	/// `ReceivedBuilderLoops`), in the order its body first receives them. Empty for nearly every scope.
	let reboundProperties: [Property]
	/// The `cycleClosedOnDeclarations` whose builder functions a cycle-closing scope in this subtree refers to
	/// from inside a `@Sendable` builder function that does not enclose them.
	private let cycleClosedOnDeclarationsReferencedFromSendableFunction: Set<BuiltDeclaration>
	/// Whether this scope's builder function is `@Sendable`: it builds a `SendableInstantiator`,
	/// `SendableErasedInstantiator`, or `SendableLazilyInstantiated`, or a cycle-closing scope in its
	/// subtree refers to it from inside a `@Sendable` builder function.
	let buildsInSendableFunction: Bool
	/// Whether this scope may declare a builder function in its parent's body: it is a property's
	/// scope that is not a cycle-closing scope.
	private let declaresBuilderFunction: Bool
	/// Whether a child's subtree closes a cycle on a scope enclosing the child, or a child is the scope
	/// a cycle beneath it closes on. Only then can this scope's body need `builderFunctionNames` to
	/// rename a builder function or to refer to one by a name other than `functionName(toBuild:)`.
	private let childrenTakePartInCycle: Bool
	/// The names a parameter of the construction of a type in this subtree declares `@escaping`, each a function type
	/// (`TypeDescription.nameDeclaredEscaping`). A parameter of a function generated code declares with such a type is
	/// spelled `@escaping`, or it could not be passed to that construction. Every receiver of a property of such a type
	/// stores it, so it declares its parameter `@escaping`, which puts the name here wherever the property is passed. A
	/// scope that calls another module's public mock, or a seam, has no scopes for what is beneath it, so the call carries
	/// the names (`PublicMockCall.typesDeclaredEscaping`, `SeamCall.typesDeclaredEscaping`).
	let typesDeclaredEscaping: Set<TypeDescription>
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

	/// Properties that will be generated as `let` constants. Mutated only by `deinit`, which has the only access.
	nonisolated(unsafe) private var propertiesToGenerate: [ScopeGenerator]
	/// Properties that this scope declares as a `let` constant, and those its type instantiates that a mock is
	/// passed instead (see `Scope.propertiesToDeclare`).
	let propertiesToDeclare: Set<Property>
	/// The `@Instantiated` dependencies of this scope's type that a mock is passed because no scope builds them (see
	/// `Scope.instantiatedDependenciesNotGenerated`), which the scopes this scope builds read as they would read the
	/// property this scope generated.
	private let instantiatedDependenciesNotGenerated: [Dependency]
	/// For a scope that calls a seam, the builders the call passes, in builder-label order; empty otherwise.
	private let holeCallArguments: [HoleCallArgument]
	/// What this scope's seam call passes each builder, in the order the seam takes them.
	private let builderCallArguments: [BuilderCallArgument]
	/// The dispatchers this scope's seam call declares.
	private let fillDispatchers: [FillDispatcher]
	/// For a scope that calls another module's public mock and fills a builder, the level functions its call declares for
	/// the builders it fills (`PublicMockLevelFunctions`); `nil` for every other scope.
	private let publicMockLevelFunctions: PublicMockLevelFunctions?
	/// For a scope that calls a seam, the holes of that seam whose builders the call passes up from the builders of
	/// the seam whose tree makes the call, in builder-label order: the caller's declarations hold no type that fulfills
	/// them. Empty otherwise.
	let passedUpHoles: [SeamSignature.Hole]
	/// Whether a scope in this generator's subtree passes up a builder (see `passedUpHoles`).
	let passesUpBuilder: Bool
	/// Whether this scope, or a scope in its subtree, calls a seam inside a fill of an enclosing call and passes one of that
	/// call's fills or dispatchers by name (`enclosingFillsPassed`): the call re-enters the enclosing call's fill.
	let holdsCallReenteringEnclosingFill: Bool
	/// For a fill, its key (see `fillKey(of:)`); `nil` for every other generator.
	let fillKey: String?
	/// For a fill, the labels of the fields of its hole's struct it binds from the struct: every field but those bound
	/// from a parameter the seam defers, which the fill reads from the caller's scope, as inline, unless a call inside a
	/// fill of the same seam call passes this fill on beneath another declaration of the label
	/// (`fillDeferredLabelsHiddenByReenteringCalls`). Empty for every other generator.
	let fillStructBoundLabels: Set<String>
	/// For a seam call, by the key of each of its fills, the labels of the hole's fields bound from deferred parameters
	/// that a declaration on the path from a fill of the call to a call inside it that passes the fill on hides: the
	/// fill, one function, would read the outer call's declaration for every call, so it reads the struct's field for
	/// them instead (see `DependencyTreeGenerator.hiddenByReenteringCalls(ofFills:)`). Empty for nearly every scope.
	let fillDeferredLabelsHiddenByReenteringCalls: [String: Set<String>]
	/// For a seam call, by the key of each of its fills, the labels of the hole's fields bound from deferred parameters held
	/// in a `LazilyInstantiated` that the fill binds from its struct and that its tree reads inside a `@Sendable` function,
	/// which cannot capture the memo: the fill binds the struct's by-value member for them instead (see
	/// `Scope.fillUnderConstruction`). Empty for nearly every scope.
	let fillDeferredLabelsReadInsideSendableFunction: [String: Set<String>]
	/// For a seam call, by the key of each of its fills, the labels some route hands the fill as a memo
	/// (`fillLabelsHandedAsMemo`) that its tree also reads as a `SendableLazilyInstantiated`, each with the instance property
	/// that wrapper holds: the fill takes that wrapper as the memo where every route can hand it
	/// (`FillDispatcher.memosHanded(toFillOf:labels:readingSendableWrapper:among:)`). Empty for nearly every scope.
	let fillSendableWrapperReads: [String: [String: Property]]
	/// For a seam call, by the key of each of its fills, the labels some route hands the fill as a memo
	/// (`fillLabelsHandedAsMemo`) whose tree reads the label but neither the memo's value nor carries it to a site: it reads
	/// the place's own field, the wrapper a type further out declares, as inline reads that declaration. The fill takes that
	/// field rather than the memo, and the levels hand it on past the deferring seam's
	/// (`FillDispatcher.Case.handsOn(_:)`). A label stays found on every later pass, where no memo is handed to show it.
	/// Empty for nearly every scope.
	let fillLabelsReadOnlyAsPlaceField: [String: Set<String>]
	/// Whether a fill in this subtree binds other fields from its struct than its call's
	/// `fillDeferredLabelsHiddenByReenteringCalls` ask, binds a memo `fillDeferredLabelsReadInsideSendableFunction` binds
	/// by value, reads a `SendableLazilyInstantiated` of a label it takes another memo of (`fillSendableWrapperReads`), or
	/// takes a memo of a label its tree reads only as the place's field (`fillLabelsReadOnlyAsPlaceField`), which another
	/// pass of `Scope.createScopeGenerator` corrects.
	let fillStructBoundLabelsChangedInTree: Bool

	/// For a fill, whether it binds a field bound from a deferred parameter from its struct, as its memo or by value
	/// (`fillDeferredLabelsReadInsideSendableFunction`): its hole is a place the called seam passes up, whose memo holds what
	/// the seam that passes it up passed (see `Scope.fillUnderConstruction`).
	let fillBindsDeferredFieldsFromStruct: Bool

	/// For a fill, the labels of its fields every route hands it as the memo of a deferred parameter a level on a carried route
	/// holds (`Scope.Fill.labelsHandedAsMemo`), which it binds from what it is handed. Empty for every other generator.
	let fillLabelsHandedAsMemo: Set<String>
	/// For a fill, by each label it takes a `LazilyInstantiated` memo of while its tree also reads the label as a
	/// `SendableLazilyInstantiated`, the routes that hand it a seam's `LazilyInstantiated`
	/// (`FillDispatcher.memosHanded(toFillOf:labels:readingSendableWrapper:among:)`): no such memo is the wrapper, so
	/// `DependencyTreeGenerator.validateFills(inTreesRootedAt:callerModule:)` reports the read. Empty for every other generator.
	let fillPlainMemoRoutesOfSendableWrapperReads: [String: [FillDispatcher.PlainMemoRoute]]

	/// For a fill, by each label some route hands it as the memo of a seam's deferred parameter
	/// (`FillDispatcher.memosHanded(toFillOf:labels:readingSendableWrapper:among:)`), each such parameter: the seam's tree, as
	/// the caller fills it, receives the label wherever the fill's tree reads that memo, so
	/// `DependencyTreeGenerator.validateFills(inTreesRootedAt:callerModule:)` judges the fill's reads against the parameter. Empty
	/// for every other generator.
	let fillMemoOriginsByLabel: [String: [SeamSignature.Hole.Field.SeamParameterOrigin]]

	/// For a fill, the fields of its hole's struct it binds from the struct (see `fillStructBoundLabels`), in
	/// field order. Empty for every other generator.
	nonisolated var fillBoundFields: [SeamSignature.Hole.Field] {
		fillFields.filter { fillStructBoundLabels.contains($0.property.label) }
	}

	/// For a fill of a place whose case is nested by type, the fields it binds that its tree reads, or that a site inside it
	/// carries, which its case's payload does not hold: it takes each as a parameter, which the dispatchers that lead to the
	/// case pass from the nearest type on the route that binds it. Empty for every other generator.
	/// A label the root dispatcher reads from the caller's scope on some route is a parameter of the form every route can
	/// hand it (`fillCallerReads`).
	nonisolated var fillParameterFields: [SeamSignature.Hole.Field] {
		guard let enumPlace = fillHole?.enumPlace, let child = propertiesToGenerate.first else { return [] }
		let carried = Set(enumPlace.values.map(\.property.label))
		return fillBoundFields.compactMap { field in
			guard !carried.contains(field.property.label), child.reads(field.property) || child.fieldsCarriedBySites.contains(field.property) else { return nil }
			return fillCallerReads.parameterByLabel[field.property.label] ?? field
		} + fillCallerReads.innerScopeParameters
	}

	/// What a level function's member hands a fill beside its case's payload (`fillParameterFields`), and, for a fill that
	/// returns a wrapper's builder (`fillReturnsWrapperBuilder`), first the fields of the payload it binds, each by itself:
	/// the builder it returns then captures what it reads, never the payload struct.
	nonisolated var fillMemberParameterFields: [SeamSignature.Hole.Field] {
		fillMemberParameterFields(takingPayloadFields: fillReturnsWrapperBuilder)
	}

	/// What a level function's member hands a fill beside its case's payload (`fillParameterFields`), first, where
	/// `takingPayloadFields`, the fields of the payload it binds, each by itself.
	nonisolated func fillMemberParameterFields(takingPayloadFields: Bool) -> [SeamSignature.Hole.Field] {
		guard takingPayloadFields, let enumPlace = fillHole?.enumPlace, let child = propertiesToGenerate.first else { return fillParameterFields }
		// Each is the fill's own field of the payload's label, which says how the fill binds it, as its body reads it: a
		// deferred parameter's memo where it `bindsMemo`, which the member hands it in place of the value.
		let boundFields = fillBoundFields
		return enumPlace.values.compactMap { value in
			guard let field = boundFields.first(where: { $0.property.label == value.property.label }),
			      child.reads(value.property) || child.fieldsCarriedBySites.contains(value.property)
			else { return nil }
			return field
		} + fillParameterFields
	}

	/// For a fill, the labels among `labels` its tree reads inside a `@Sendable` function, or hands to a nested seam that
	/// takes them `@Sendable`, where no declaration inside the tree hides them, as
	/// `DependencyTreeGenerator.receivers(in:of:instantiables:)` finds a seam's tree reading its parameters
	/// (`ParameterReads`): the fill's bound fields stand where the seam's parameters do. The fill's own function is not one
	/// of those functions: what it binds is a local of that function. A scope that closes a lazy cycle reads no label from
	/// above the function it closes on, which takes each label the closer passes as a parameter (`CycleParameter`), so a
	/// closer adds no read here.
	nonisolated func labelsReadInsideSendableFunction(among labels: Set<String>) -> Set<String> {
		var labelsRead = Set<String>()
		var generatorsToVisit = children.map { (generator: $0, insideSendable: $0.buildsInSendableFunction, declaredLabels: Set<String>()) }
		while let (visited, insideSendable, declaredLabels) = generatorsToVisit.popLast() {
			func recordRead(of label: String, insideSendable: Bool) {
				if insideSendable, labels.contains(label), !declaredLabels.contains(label) {
					labelsRead.insert(label)
				}
			}
			// A nested seam's call reads what it passes where the call is, and a parameter it takes `@Sendable` inside a
			// `@Sendable` autoclosure.
			for parameter in visited.seamCallParameters ?? [] {
				recordRead(of: parameter.property.label, insideSendable: insideSendable || parameter.deferral == .deferred(isSendable: true))
			}
			let visitedLabels = Set(visited.providedProperties.map(\.label))
			for dependency in visited.builtInstantiable?.dependencies ?? [] {
				switch dependency.source {
				case .received:
					recordRead(of: dependency.property.label, insideSendable: insideSendable)
				case let .aliased(fulfillingProperty, _, _):
					// An alias that keeps its fulfilling property's label is not in scope where that property is read.
					if fulfillingProperty.label == dependency.property.label || !visitedLabels.contains(fulfillingProperty.label) {
						recordRead(of: fulfillingProperty.label, insideSendable: insideSendable)
					}
				case .instantiated, .forwarded:
					continue
				}
			}
			let childDeclaredLabels = declaredLabels.union(visitedLabels)
			for child in visited.children {
				generatorsToVisit.append((
					generator: child,
					insideSendable: insideSendable || child.buildsInSendableFunction || visited.buildsInSendableFunction(ofFill: child),
					declaredLabels: childDeclaredLabels.union(child.fillStructBoundLabels),
				))
			}
		}
		return labelsRead
	}

	/// For a fill of a case nested by type, what it reads of the caller's scope through the root dispatcher. Empty for
	/// every other generator.
	let fillCallerReads: FillCallerReads

	/// For a fill, the fields it can bind: its hole's struct's, or, for a place whose case is nested by type, those of every
	/// place of the case, each label once (see `init(fill:…)`). Empty for every other generator.
	let fillFields: [SeamSignature.Hole.Field]
	/// For a fill, the places it stands for: its hole, or, for a place whose case is nested by type, every place of the case,
	/// in the order the builders reach them. Empty for every other generator.
	let fillCaseHoles: [SeamSignature.Hole]

	/// For a fill, the declarations on the paths of the places it stands for that their structs do not carry, each label
	/// once, in the order the places first declare them. Empty for every other generator.
	nonisolated var fillUncarriedDeclarations: [SeamSignature.Hole.UncarriedDeclaration] {
		var declarations = [SeamSignature.Hole.UncarriedDeclaration]()
		var seenLabels = Set<String>()
		for place in fillCaseHoles {
			for declaration in place.uncarriedDeclarations where seenLabels.insert(declaration.property.label).inserted {
				declarations.append(declaration)
			}
		}
		return declarations
	}

	/// For a fill, the labels some place it stands for declares on its path without its struct carrying them and without a
	/// nearer field of theirs: on that place's route the nearest declaration is one the fill cannot read, as inline's tree
	/// reads it there, whatever the other places carry. Empty for every other generator.
	nonisolated var fillLabelsUncarriedOnSomeRoute: Set<String> {
		Set(fillCaseHoles.flatMap { place in
			let fieldLabels = Set(place.fields.map(\.property.label))
			return place.uncarriedDeclarations.map(\.property.label).filter { !fieldLabels.contains($0) }
		})
	}

	/// Whether a fill's code is generated: `false` for a fill of a place nested by type whose case another place's fill of
	/// the same call generates. Such a fill is built and judged as any, and every route of the case calls the other.
	let fillEmitsCode: Bool

	/// The fills of enclosing calls that calls in this subtree refer to by name, each by its key with its function's
	/// name, which no builder function declared between such a call and the fill may share (see `builderFunctionNames`).
	/// A call refers to such a fill when it passes it as an argument, and to a level function of the enclosing call that it
	/// reuses when a case of one of its own dispatchers calls that function (`FillDispatcher.Case.Target.reusedCarriedInnerScopes`).
	let referencedFillNamesByKey: [String: String]
	/// The keys of `referencedFillNamesByKey` referred to from inside a `@Sendable` builder function that does not
	/// enclose the fill, or passed to a seam that takes the fill `@Sendable`.
	let fillKeysReferencedFromSendableFunction: Set<String>
	/// For a seam call, the keys of its fills whose function is `@Sendable`, which `buildsInSendableFunction(ofFill:)` reads
	/// (see `sendableFills(of:referencedFromSendableFunctions:)`).
	private let sendableFillKeys: Set<String>
	/// For a seam call, the keys of its fills generated in the one dispatcher case that calls them, not as functions of
	/// their own: a fill nothing else refers to by name, which is `@Sendable` exactly when its dispatcher is.
	private let inlinableFillKeys: Set<String>
	/// The keys of the fills and dispatchers of enclosing calls that this scope's code, or a scope's beneath it, calls or
	/// passes by name.
	let namedFillKeys: Set<String>
	/// The payloads of the cases on the routes to the places beneath this scope that the seam's tree binds just before this
	/// scope's builder function (`SeamHoles.valuesBindings(at:)`): empty but where a case nested by type leads through this
	/// scope's property.
	private let valuesBindings: [SeamHoles.ValuesBinding]
	/// The structs the member calls the seam's tree makes at the top of this scope's builder function return, a `@Sendable`
	/// function (`SeamHoles.memberCallsInsideFunction(at:)`): empty but where a builder struct's `@Sendable` member leads
	/// through this scope's property.
	private let memberCallsInsideFunction: [SeamHoles.ValuesBinding]
	/// Whether each `@Sendable` local function this scope declares is spelled `@Sendable nonisolated`: in the tree of a
	/// seam a builder of which takes a builder struct (`SeamHoles.declaresBuilderStructs`).
	private let sendableFunctionsAreNonisolated: Bool
	/// Whether a fill builds this scope's property: the fill returns the value a builder returns, so a wrapper's scope
	/// declares its builder function and returns what the function builds, and leaves the wrapper to the seam.
	private let isBuiltByFill: Bool
	/// For a fill, and the scope of the property it builds, whether the fill fills an instantiator's place for a level
	/// function, a member of a builder struct, and so returns the builder the wrapper keeps: a closure that takes the
	/// forwarded value and calls the property's builder function, which captures no payload struct.
	private let fillReturnsWrapperBuilder: Bool
	/// For the scope of the property a fill that returns the builder a wrapper keeps builds (`fillReturnsWrapperBuilder`),
	/// the names of the fill's parameters that hold the functions the inner seam's members return for the fill's place,
	/// which take the value the wrapper forwards and return the struct of the fill's own level: the property's builder
	/// function calls each with what it was forwarded, at its top, and binds the struct under the parameter's name, so the
	/// builder the fill returns captures no payload.
	private let innerScopesCalledWithForwardedValue: [String]
	/// See `MockParameterNode.valuesBindings`: each field read as the scope's parent reads its label, as production's are.
	nonisolated var valuesBindingsBeforeBuilderFunction: [MockParameterNode.ValuesBinding] {
		valuesBindings.map { MockParameterNode.ValuesBinding(binding: $0, lazilyInstantiatedInstanceProperties: callSiteLazilyInstantiatedInstanceProperties) }
	}

	/// See `MockParameterNode.memberCallsInsideBuilderFunction`: each field read as the scope's parent reads its label.
	nonisolated var memberCallsInsideBuilderFunction: [MockParameterNode.ValuesBinding] {
		memberCallsInsideFunction.map { MockParameterNode.ValuesBinding(binding: $0, lazilyInstantiatedInstanceProperties: callSiteLazilyInstantiatedInstanceProperties) }
	}

	/// Whether this scope's generated subtree holds a site of a hole of the seam whose tree is generated, on this scope's
	/// path. A child starts after its siblings that hold no place by `startsAsCarrier(_:)`, which reads this only where
	/// `placeHoldingProperties` is `nil` (see `orderedPropertyToGenerateIndices`).
	let containsBuildSite: Bool

	/// Whether a fill whose tree this scope's property roots is handed the structs of its own level
	/// (`FillCallerReads.innerScopeParameters`): its tree builds a place, or a call that passes one up, whose case carries one,
	/// or a call that re-enters an enclosing call's fill, whose case's member is called on one. A fill that builds its type in
	/// a `@Sendable` builder function of the type's own is handed none: its case carries no inner scope
	/// (`SeamDeclarationGraph.FilledBuilder.carriesInnerScope`), and what its tree reads of the seam's builders is bound at the
	/// top of that function, so a struct it took would be a parameter, and a binding, nothing reads.
	nonisolated var readsFillInnerScopes: Bool {
		!buildsInSendableFunction && (containsBuildSite || passesUpBuilder || holdsCallReenteringEnclosingFill)
	}

	/// The properties of this scope's type that hold a place of the seam whose tree is generated, by the seam's declaration
	/// graph (`SeamDeclarationGraph`): a fact of the type, the same on every path, which orders this scope's children. `nil`
	/// where the order by path is the same, which `Scope.createScopeGenerator` checks, inside a fill, whose tree is built
	/// with the filled seam's stack, and for every scope that is no type's.
	private let placeHoldingProperties: Set<Property>?

	/// Whether `child`, a child of this scope, starts after its siblings that hold no place: it holds one by
	/// `placeHoldingProperties`, or, where this scope has none or the child declares no property (a fill), its subtree
	/// holds a site on this path (`containsBuildSite`).
	nonisolated func startsAsCarrier(_ child: ScopeGenerator) -> Bool {
		if let placeHoldingProperties, let property = child.property {
			placeHoldingProperties.contains(property)
		} else {
			child.containsBuildSite
		}
	}

	/// The fields the scope structs of the sites in this generator's subtree carry whose nearest declaration on each
	/// site's path is above this scope: a fill the seam generates binds each of the filled seam's fields they carry,
	/// whether or not its own tree reads it.
	let fieldsCarriedBySites: Set<Property>
	/// The received properties that are in scope only as the instance of a `LazilyInstantiated` property created
	/// further up the tree. Passing one to this scope’s initializer reads that instance, which instantiates it.
	private let lazilyInstantiatedInstanceProperties: Set<Property>
	/// Whether the property an alias renames is in scope only as the instance of a `LazilyInstantiated` property.
	private let fulfillingPropertyIsLazilyInstantiatedInstance: Bool
	/// The by-value property with which this scope’s siblings and their subtrees receive the instance of the
	/// lazily instantiated property this scope declares. `nil` when it declares none.
	private let declaredLazilyInstantiatedInstanceProperty: Property?
	/// For an `onlyIfAvailable` alias, whether the declared property it is bound from may be `nil`: an optional
	/// property it reads in place of its fulfilling property's non-optional form, a parameter made optional, or a
	/// seam's optional parameter. `false` for every other scope.
	private let fulfillingBindingIsOptional: Bool
	/// For an alias the seam root declares that keeps the label of a deferred parameter it retypes, the call of the
	/// parameter's autoclosure it is bound from (`SeamRoot.autoclosureCallByLabel`); `nil` for every other generator.
	private let fulfillingExpression: String?
	let property: Property?
	/// The comment that ends each line that constructs this scope's type (`Scope.builtInlineSeamComment`).
	private let builtInlineSeamComment: String?
	/// Whether this scope, in the tree of a fill a mock declares for another module's public mock, builds its type with
	/// its hand-written mock, as the mock's tree built inline would (`Scope.createScopeGenerator`).
	private let constructsWithHandWrittenMock: Bool
	/// How a mock tree calls the public mock another module generated for this scope's type, or `nil` for a scope
	/// that builds its type (see `Scope.publicMockCall`).
	let publicMockCall: PublicMockCall?
	/// For a public mock's root, the builders its `mock()` takes; `nil` for every other generator.
	let mockBuilders: DependencyTreeGenerator.ShapedBuilders?
	/// In a seam's tree, the names its generated initializer binds for its deferred parameters and its builders, which
	/// code anywhere in the tree may read and no `__safeDI_<label>_received` function may hide (see
	/// `namesReceivedFunctionsAvoid`). Empty outside a seam's tree.
	private let namesBoundBySeam: Set<String>

	/// For a scope that calls another module's public mock: what the call passes each builder it fills or hands up through a
	/// case of the calling public mock's own enum, by label. A builder it passes up as the calling internal mock's parameter
	/// is passed as the leaf's dependency of its label, which has no entry.
	nonisolated var holeArgumentValuesByLabel: [String: String] {
		guard publicMockCall != nil else { return [:] }
		var valuesByLabel = [String: String]()
		for builderCallArgument in builderCallArguments where !builderCallArgument.value.isEmpty {
			valuesByLabel[builderCallArgument.label] = builderCallArgument.value
		}
		return valuesByLabel
	}

	/// What an override closure that builds the public mock of another module this scope calls is handed for each builder the
	/// called `mock()` takes, by label, or `nil` where the call holds no builder a person writes for some builder, and its node
	/// then offers no closure: the closure passes what it is handed on to `mock()`, and written code is handed nothing
	/// generated. Only for a call whose called mock takes no `SafeDIOverrides`, whose node's member is that closure; such a
	/// mock builds nothing itself, so it has one level, which binds its parameters and holds its places.
	///
	/// A builder an internal mock passes up whole is handed as the mock takes it. A builder whose one place the call fills is
	/// handed a function over its fill, which takes each value the fill reads (`fillTakesPayloadFields`),
	/// handed the value the call passes the called mock's parameter of that label: where a value the fill reads is no such
	/// parameter of that type, being another of the called mock's places or a value it renames, the call can hand no builder.
	/// A public mock's body holds only the struct its caller built, so where it passes a place up, nothing can be handed
	/// either (`BuilderCallArgument.OverrideHanding`). Nor where a call inside the call's fills re-enters one of its level
	/// functions and a fill reads a value of the caller's scope: the fill then takes that value from the level function
	/// (`PublicMockLevelFunctions.Reentry`), so it takes more than its payload. Decided when the tree is built, for the
	/// whole call: the struct that holds the member is shared by every node of its type in the module's mocks of one access,
	/// which all decide alike, since a call fills or passes up a place whatever mock's tree makes it.
	///
	/// A deliberate gap, commented where the member is typed (`MockParameterNode.offersOverrideClosure`): the closure could be
	/// offered there by unwrapping the called mock's struct in generated code, a later addition that breaks nothing.
	nonisolated var publicMockOverrideBuilders: [String: PublicMockOverrideBuilder]? {
		guard let publicMockCall, !publicMockCall.takesOverrides else { return nil }
		let builderLabels = Set(builderCallArguments.map(\.label))
		let parameterTypesByLabel = Dictionary(
			(builtInstantiable?.mockInitializer?.arguments ?? []).filter { !builderLabels.contains($0.innerLabel) }.map { ($0.innerLabel, $0.typeDescription) },
			uniquingKeysWith: { first, _ in first },
		)
		var buildersByLabel = [String: PublicMockOverrideBuilder]()
		for builderCallArgument in builderCallArguments {
			switch builderCallArgument.overrideHanding {
			case .none:
				return nil
			case .callersBuilder:
				buildersByLabel[builderCallArgument.label] = .callersBuilder(builderCallArgument.value)
			case .fills:
				// The called mock's one level holds every place the builder reaches, so its root level function's every member is a
				// fill, which takes no value beside its payload. One builder a person writes stands for every place, so every place
				// must be filled by one fill: a fill is generated per place, so a builder with two places gets no closure.
				let members = builderCallArgument.builderStruct?.rootDispatcherKey.flatMap { publicMockLevelFunctions?.rootMembers(ofDispatcherKeyed: $0) } ?? []
				let fillTargets = members.compactMap(\.fillTakingOnlyItsPayload)
				guard fillTargets.count == members.count, Set(fillTargets.map(\.key)).count == 1, let target = fillTargets.first, let fill = propertiesToGenerate.first(where: { $0.fillKey == target.key && $0.fillEmitsCode }), fill.fillHole?.forwardedType == nil || fill.fillReturnsWrapperBuilder else { return nil }
				let fields = fill.fillMemberParameterFields(takingPayloadFields: true)
				guard fields.allSatisfy({ parameterTypesByLabel[$0.property.label] == $0.property.typeDescription }) else { return nil }
				buildersByLabel[builderCallArgument.label] = .fill(
					key: target.key,
					functionName: target.name,
					parameterLabels: fields.map(\.property.label),
					returnsWrapperBuilder: fill.fillReturnsWrapperBuilder,
					forwardsNothing: fill.fillHole?.forwardedType == nil,
				)
			}
		}
		return buildersByLabel
	}

	/// What an override closure of a call of another module's public mock is handed for one builder
	/// (`publicMockOverrideBuilders`).
	enum PublicMockOverrideBuilder: Sendable {
		/// The builder the calling internal mock takes, which it passes up whole.
		case callersBuilder(String)
		/// A function over the fill of `key`, `functionName`, which takes the values of `parameterLabels`. A fill that returns
		/// a wrapper's builder is handed as its call, which returns the builder, unless its place forwards nothing
		/// (`forwardsNothing`): the called `mock()` then takes a builder that takes nothing, so it is handed a closure that
		/// calls the wrapper's builder with `()`.
		case fill(key: String, functionName: String, parameterLabels: [String], returnsWrapperBuilder: Bool, forwardsNothing: Bool)

		/// The expression handed, given the expression the call passes the called mock's parameter of each label.
		func expression(argumentByLabel: [String: String]) -> String {
			switch self {
			case let .callersBuilder(value):
				return value
			case let .fill(_, functionName, parameterLabels, returnsWrapperBuilder, forwardsNothing):
				let arguments = parameterLabels.map { "\($0.spelledAsArgumentLabel): \(argumentByLabel[$0] ?? $0)" }.joined(separator: ", ")
				let call = "\(functionName)(\(arguments))"
				if !returnsWrapperBuilder {
					return "{ \(call) }"
				} else if forwardsNothing {
					return "{ \(call)(()) }"
				} else {
					return call
				}
			}
		}
	}

	/// Whether this scope's call of another module's public mock passes a fill or a dispatcher, its own or an enclosing
	/// call's, which the node that makes the call declares in a builder function of its own.
	nonisolated var fillsABuilder: Bool {
		publicMockCall != nil
			&& (!fillDispatchers.isEmpty || propertiesToGenerate.contains { $0.fillKey != nil } || builderCallArguments.contains { $0.enclosingFill != nil })
	}

	/// For a scope that calls another module's public mock and fills its builders, the code of the fills, which a mock
	/// declares before the call, by the `propertiesGeneratedLater` the fills are generated with: each builds the hole's
	/// property as the module that declares the fulfilling type builds it. Empty until
	/// `prepareFillCode(propertiesGeneratedLater:)` returns.
	private var fillCodeByPropertiesGeneratedLater = [Set<Property>: [String]]()

	/// Generates the code of the fills with `propertiesGeneratedLater`, those of the body of the builder function of the
	/// node that makes the call (see `MockParameterNode.fillPropertiesGeneratedLater`), which a mock's emission reads
	/// (`fillCode(propertiesGeneratedLater:)`) and cannot throw. A receive inside a fill of a property the scopes
	/// enclosing the call generate after it is then passed `nil`, as it is outside a fill, rather than a binding declared
	/// after the fill.
	/// `fillPlaceBindings` are the bindings of the places inside the fills an internal mock declares (`FillPlace`).
	func prepareFillCode(propertiesGeneratedLater: Set<Property>, fillPlaceBindings: FillPlaceBindings) async throws {
		// A mock is hosted as its text until the mock body is planned (`.claude/rules/emission-decisions.md`).
		fillCodeByPropertiesGeneratedLater[propertiesGeneratedLater] = try await generateProperties(
			propertiesGeneratedLater: propertiesGeneratedLater,
			enclosingFunctionNames: [:],
			leadingMemberWhitespace: "",
			fillPlaceBindings: fillPlaceBindings,
		).map { $0.spelled() }
	}

	/// The code of the fills `prepareFillCode(propertiesGeneratedLater:)` generated with `propertiesGeneratedLater`.
	func fillCode(propertiesGeneratedLater: Set<Property>) -> [String] {
		fillCodeByPropertiesGeneratedLater[propertiesGeneratedLater, default: []]
	}

	private struct UnavailablePropertiesCacheKey: Hashable {
		let unavailableProperties: Set<Property>
		let propertiesGeneratedLater: Set<Property>
		let builderFunctionNames: BuilderFunctionNames
		let fillPlaceBindings: FillPlaceBindings
	}

	/// The tasks generating this scope's dependency tree code for each context, until each finishes.
	private var unavailablePropertiesToGenerateCodeTask = [UnavailablePropertiesCacheKey: Task<GeneratedCode, Error>]()
	/// This scope's finished dependency tree code for each context.
	private var unavailablePropertiesToGeneratedCode = [UnavailablePropertiesCacheKey: GeneratedCode]()
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
	private var orderedPropertiesToGenerate: LazyMapSequence<[Int], ScopeGenerator> {
		orderedPropertyToGenerateIndices.lazy.map { self.propertiesToGenerate[$0] }
	}

	/// The indices in `propertiesToGenerate` of `orderedPropertiesToGenerate`. Kept as indices so that
	/// `propertiesToGenerate` holds the only references this generator has to its children (see `deinit`).
	private lazy var orderedPropertyToGenerateIndices: [Int] = computeOrderedPropertyToGenerateIndices()

	/// `orderedPropertyToGenerateIndices`, computed afresh, which reads nothing but what the generator and its
	/// children hold from their creation, so a walk of a seam's tree can order a scope's children without awaiting it.
	/// - Parameter startingCarriersLast: Whether a child that holds a place starts after its siblings that hold none
	///   (`startsAsCarrier(_:)`), as the build does. `false` gives the inline build's order, declaration order with each
	///   child after the siblings it depends upon, in which a mock's `SafeDIOverrides` and each configuration take their
	///   members (`MockParameterNode.inlineOrderPosition`).
	nonisolated func computeOrderedPropertyToGenerateIndices(startingCarriersLast: Bool = true) -> [Int] {
		let siblingGraph = Self.siblingGraph(of: propertiesToGenerate, requiredOnlyIfAvailableAliasProperties: requiredOnlyIfAvailableAliasProperties)
		// Each child is ordered as a unit of its own, but a loop of builders that receive one another, which is ordered as
		// one unit (see `ReceivedBuilderLoops`): a receive inside a loop reads a rebinding in the receiving member's function,
		// so it orders nothing, and creating one member's wrapper uses every member's function, which captures what the
		// member reads, so the unit waits on everything any member waits on outside it, and whatever waits on a member
		// follows the unit. Its members are emitted together, in declaration order, the renames this scope declares of them
		// after the members they rename. A graph without a loop is ordered child by child.
		let unitByIndex = propertiesToGenerate.indices.map { receivedBuilderLoops.loopByChildIndex[$0] ?? $0 }
		var membersByUnit = [Int: [Int]]()
		if !receivedBuilderLoops.loopByChildIndex.isEmpty {
			for index in propertiesToGenerate.indices where receivedBuilderLoops.loopByChildIndex[index] != nil && !propertiesToGenerate[index].isAlias {
				membersByUnit[unitByIndex[index], default: []].append(index)
			}
			for index in propertiesToGenerate.indices where receivedBuilderLoops.loopByChildIndex[index] != nil && propertiesToGenerate[index].isAlias {
				membersByUnit[unitByIndex[index], default: []].append(index)
			}
		}
		var siblingDependencies = siblingGraph.dependencies
		if !membersByUnit.isEmpty {
			var unitDependencies = propertiesToGenerate.indices.map { _ in Set<Int>() }
			for index in propertiesToGenerate.indices {
				for dependencyIndex in siblingDependencies[index] where unitByIndex[dependencyIndex] != unitByIndex[index] {
					unitDependencies[unitByIndex[index]].insert(unitByIndex[dependencyIndex])
				}
			}
			siblingDependencies = unitDependencies
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

		// Each sibling follows the siblings it depends upon, depth first in index order. The search keeps its own path, since
		// a scope can have as many children depending on one another in turn as the module has types.
		var orderedIndices = [Int]()
		// A seam call's fills declare no property, and each is generated. A loop is visited as the unit its first member
		// stands for.
		var unfulfilledIndices = Set(siblingGraph.siblings.map { unitByIndex[$0.index] }).union(propertiesToGenerate.indices.filter { propertiesToGenerate[$0].property == nil })
		// In a seam's tree, a child that holds a place of one of its holes – a carrier – starts last: first every child
		// that is no carrier and depends on none through the edges above, in index order, then the rest, in index order.
		// Whether a child holds a place is a fact of this scope's type (`startsAsCarrier(_:)`), so every build of the type
		// starts its children in one order, a build on which the child closes a cycle included. No edge is added or
		// dropped, so every receive keeps the availability it has; the start order only puts every sibling that can be
		// built before a site there, so the site's scope struct carries it. Without a carrier the order is the index
		// order. A sibling that depends on a carrier and is declared after a later carrier is built after that one, so a
		// fill of the later carrier's site that reads it is reported, not supported
		// (`FillFinding.Kind.declarationBoundAfterSite`): a deliberate gap, which a finer order could close later.
		let startIndices: [Int] = if startingCarriersLast, propertiesToGenerate.contains(where: startsAsCarrier) {
			{
				let carrierIndices = propertiesToGenerate.indices.filter { startsAsCarrier(propertiesToGenerate[$0]) }.map { unitByIndex[$0] }
				let reachesCarrier = propertiesToGenerate.indices.map { index in
					carrierIndices.contains { dependsOn($0, from: unitByIndex[index]) }
				}
				return propertiesToGenerate.indices.filter { !reachesCarrier[$0] }.map { unitByIndex[$0] } + propertiesToGenerate.indices.filter { reachesCarrier[$0] }.map { unitByIndex[$0] }
			}()
		} else {
			propertiesToGenerate.indices.map { unitByIndex[$0] }
		}
		/// Appends the children `unit` stands for.
		func appendUnit(_ unit: Int) {
			if let members = membersByUnit[unit] {
				orderedIndices.append(contentsOf: members)
			} else {
				orderedIndices.append(unit)
			}
		}
		for startIndex in startIndices where unfulfilledIndices.contains(startIndex) {
			// Mark as fulfilled before descending to prevent cycles.
			unfulfilledIndices.remove(startIndex)
			// Each sibling on the path, with the siblings it depends upon and the position of the next one to fulfill.
			var path = [(index: startIndex, dependencyIndices: siblingDependencies[startIndex].sorted(), nextDependencyPosition: 0)]
			while let (index, dependencyIndices, dependencyPosition) = path.last {
				if dependencyPosition < dependencyIndices.count {
					path[path.count - 1].nextDependencyPosition += 1
					let dependencyIndex = dependencyIndices[dependencyPosition]
					if unfulfilledIndices.remove(dependencyIndex) != nil {
						path.append((index: dependencyIndex, dependencyIndices: siblingDependencies[dependencyIndex].sorted(), nextDependencyPosition: 0))
					}
				} else {
					appendUnit(index)
					path.removeLast()
				}
			}
		}
		return orderedIndices
	}

	/// The edges between the children of one scope that decide their order, and the receives only if available among them
	/// that the order leaves `nil`.
	struct SiblingGraph {
		/// The first child declaring each property, with the property that receives its instance when it is lazily
		/// instantiated, and its index among the children.
		var siblings = [(property: Property, instanceProperty: Property?, index: Int)]()
		/// For each child, the siblings it is built after: those its tree requires, and those it receives only if available
		/// where that closes no cycle among the siblings, considered in sibling order. Never the child itself.
		var dependencies = [Set<Int>]()
		/// The receives only if available that the order leaves `nil` because the sibling received already waits on the
		/// receiver, in the order they were considered, with a child's receive of its own property, which is still being
		/// built inside its tree.
		var receivesLeftNil = [(receiver: Int, sibling: Int)]()
		/// The children whose tree requires the child's own property.
		var childrenRequiringThemselves = Set<Int>()
	}

	/// The edges between `children`, the children of one scope (see `SiblingGraph`).
	///
	/// A child depends on a sibling when the child's subtree receives the sibling. A required receive must be honored, and
	/// the subtree's receive is required when any receiver in it requires the sibling, or requires an `onlyIfAvailable`
	/// alias the sibling fulfills (see `requiredAliasFulfillingProperties`). A `@Received(onlyIfAvailable: true)` receive is
	/// honored only when it does not close a cycle among the siblings — e.g. when `b`'s subtree receives `c` only if
	/// available but `c` receives `b`, `c` cannot be built before `b`. Receives are considered in sibling order, so the
	/// result is deterministic, and it matches a plain topological order whenever every receive can be honored.
	nonisolated private static func siblingGraph(
		of children: [ScopeGenerator],
		requiredOnlyIfAvailableAliasProperties: Set<Property>,
	) -> SiblingGraph {
		var siblingGraph = SiblingGraph()
		// A property can be listed more than once — a mock root promotes a received
		// property that a promoted scope receives even when the root already
		// instantiates it. Only the first child for each property is generated.
		// A lazily instantiated sibling is also received by value, as the instance it creates.
		var listedProperties = Set<Property>()
		for (index, scope) in children.enumerated() {
			if let property = scope.property, listedProperties.insert(property).inserted {
				siblingGraph.siblings.append((property, scope.declaredLazilyInstantiatedInstanceProperty, index))
			}
		}
		let siblings = siblingGraph.siblings
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
		var siblingsByLabel = [String: [(property: Property, index: Int)]]()
		for sibling in siblings {
			siblingsByLabel[sibling.property.label, default: []].append((sibling.property, sibling.index))
		}
		var childrenRequiringThemselves = Set<Int>()
		var siblingDependencies = children.enumerated().map { scopeIndex, scope in
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
			// A required optional property resolves to a mock root's promoted sibling of its non-optional form, which the
			// mock promotes once for both forms.
			for property in scope.unwrappedOptionalRequiredReceivedProperties {
				if let siblingIndex = siblingIndexByProperty[property] {
					dependencies.insert(siblingIndex)
				}
			}
			// A property the child's tree requires through an `onlyIfAvailable` alias is read from the nearest declaration
			// of its label: a sibling that declares the label is built first where it provides a form the alias reads. The
			// child's own property is still being built inside its tree, where the alias is `nil`.
			for property in scope.requiredAliasFulfillingProperties {
				for sibling in siblingsByLabel[property.label, default: []]
					where sibling.index != scopeIndex && Self.provides(sibling.property, aFormReadBy: property)
				{
					dependencies.insert(sibling.index)
				}
			}
			// A child's tree that requires the child's own property receives the declaration being built: an instantiator,
			// which the child's builder function rebinds (see `ReceivedBuilderLoops`). It orders nothing.
			if dependencies.remove(scopeIndex) != nil {
				childrenRequiringThemselves.insert(scopeIndex)
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
		// An `onlyIfAvailable` alias a receiver requires is built after the sibling that
		// declares its fulfilling property's label, as a required alias is, where that sibling
		// provides a form the alias reads. A sibling that receives the alias only if available
		// then waits on it only when that does not close a cycle (below).
		for case let (index, aliasProperty?) in children.map(\.property).enumerated()
			where requiredOnlyIfAvailableAliasProperties.contains(aliasProperty)
		{
			guard let fulfillingProperty = children[index].onlyIfAvailableAliasFulfillingProperty else { continue }
			for sibling in siblingsByLabel[fulfillingProperty.label, default: []] where Self.provides(sibling.property, aFormReadBy: fulfillingProperty) {
				siblingDependencies[index].insert(sibling.index)
			}
		}
		// Then each `onlyIfAvailable` receive, in sibling order, unless the sibling it
		// would wait on already waits on the receiver. The `onlyIfAvailable` aliases go
		// first: each waits on the sibling that fulfills it, so it is created once that
		// sibling is built, and a sibling whose tree receives the alias only if available
		// is then generated with the alias unavailable, as it is still being built.
		for considersAliases in [true, false] {
			for (index, scope) in children.enumerated()
				where (scope.onlyIfAvailableAliasFulfillingProperty != nil) == considersAliases
				&& !scope.onlyIfAvailableUnwrappedReceivedProperties.isEmpty
			{
				for sibling in siblings
					where scope.onlyIfAvailableUnwrappedReceivedProperties.contains(sibling.property.asUnwrappedProperty)
					|| sibling.instanceProperty.map(scope.onlyIfAvailableUnwrappedReceivedProperties.contains) == true
				{
					if dependsOn(index, from: sibling.index) {
						siblingGraph.receivesLeftNil.append((receiver: index, sibling: sibling.index))
					} else {
						siblingDependencies[index].insert(sibling.index)
					}
				}
			}
		}
		siblingGraph.dependencies = siblingDependencies
		siblingGraph.childrenRequiringThemselves = childrenRequiringThemselves
		return siblingGraph
	}

	/// The loops among a scope's children, builders whose trees receive one another, and what each member's builder function
	/// rebinds.
	///
	/// Arrows run from each child to each sibling its tree receives, and from a child whose tree receives its own property to
	/// itself. A loop is a strongly connected set of builders – instantiators, and the renames the scope declares of them that
	/// do not erase them – with an arrow inside it. A receive inside a loop is read from a wrapper the receiving member's
	/// function makes again of the received member's function (a rebinding), so no wrapper holds itself and a tree released
	/// by its owner is freed. Validation rejects a cycle of required receives with any other property on it.
	///
	/// A receive only if available is decided in two passes. The first is the order's (see `siblingGraph(of:)`), in sibling
	/// order. The second takes every receive the first left `nil` whose receiver and received sibling are both builders. It
	/// gives a child's receive of its own property always, since that closes no circle but the builder's own, and adds every
	/// other one to the graph at once and gives each exactly when its strongly connected component holds only builders, so
	/// it reads no order: renaming or reordering cannot change it. The loops are then found in the graph of the arrows
	/// the order keeps and the receives the second pass gives, never with a receive it leaves `nil`, which reads nothing: a
	/// loop of builders, one member included, beside a receive left `nil` that closes a circle through a value is still a loop.
	struct ReceivedBuilderLoops: Equatable, Sendable {
		/// For each child on a loop, by its index among the children, the loop it is on, named by the index of its first
		/// member.
		var loopByChildIndex = [Int: Int]()
		/// For each child on a loop, by its index among the children, the properties of the siblings its tree receives
		/// inside the loop – its own among them when its tree receives it – which its builder function rebinds.
		var reboundPropertiesByChildIndex = [Int: Set<Property>]()
	}

	/// Whether this scope, one of `siblings`, the children of one scope, is a builder that can be on a loop (see
	/// `ReceivedBuilderLoops`): it builds an instantiator, in a builder function of its own or, closing a cycle, in the one
	/// it closes on, or it is a rename of one that does not erase it – required, or only if available of an instantiator a
	/// sibling builds, which it is then always bound from.
	nonisolated private func isLoopBuilder(amongSiblings siblings: [ScopeGenerator]) -> Bool {
		switch scopeData {
		case let .property(_, property, _, _, _, _):
			// A cycle-closing scope's wrapper hands the function it closes on.
			return Self.isBuilder(property)
		case let .alias(property, fulfillingProperty, erasedToConcreteExistential, onlyIfAvailable, _):
			guard !erasedToConcreteExistential, Self.isBuilder(property) else { return false }
			if onlyIfAvailable {
				return siblings.contains { sibling in
					guard case let .property(_, siblingProperty, _, _, _, _) = sibling.scopeData else { return false }
					return siblingProperty.label == fulfillingProperty.label
						&& Self.isBuilder(siblingProperty)
						&& Self.provides(siblingProperty, aFormReadBy: fulfillingProperty)
				}
			} else {
				return true
			}
		case .root, .hole, .fill:
			return false
		}
	}

	/// Whether this scope is a rename its scope declares.
	nonisolated private var isAlias: Bool {
		switch scopeData {
		case .alias:
			true
		case .root, .property, .hole, .fill:
			false
		}
	}

	/// Whether `property` is an instantiator of any kind.
	nonisolated static func isBuilder(_ property: Property) -> Bool {
		switch property.propertyType {
		case .instantiator, .erasedInstantiator, .sendableInstantiator, .sendableErasedInstantiator:
			true
		case .constant, .lazilyInstantiated, .sendableLazilyInstantiated:
			false
		}
	}

	/// The loops among `children`, the children of one scope (see `ReceivedBuilderLoops`).
	nonisolated private static func receivedBuilderLoops(
		of children: [ScopeGenerator],
		requiredOnlyIfAvailableAliasProperties: Set<Property>,
	) -> ReceivedBuilderLoops {
		let isBuilder = children.map { $0.isLoopBuilder(amongSiblings: children) }
		// Nearly every scope has fewer than two builders and receives none of them inside its own tree.
		guard isBuilder.contains(true) else { return ReceivedBuilderLoops() }
		let siblingGraph = siblingGraph(of: children, requiredOnlyIfAvailableAliasProperties: requiredOnlyIfAvailableAliasProperties)
		// The second pass's receives: each the first left `nil` between two builders.
		var candidates = [(receiver: Int, sibling: Int)]()
		// A receive given here is checked like any given receive: a `Sendable` builder's receive of one that is not is
		// `nonSendableWrapperCaptures`' error, as it is outside a loop.
		for receive in siblingGraph.receivesLeftNil where isBuilder[receive.receiver] && isBuilder[receive.sibling] {
			candidates.append(receive)
		}
		guard !candidates.isEmpty || !siblingGraph.childrenRequiringThemselves.isEmpty || siblingGraph.dependencies.indices.contains(where: { index in
			isBuilder[index] && siblingGraph.dependencies[index].contains { isBuilder[$0] }
		}) else { return ReceivedBuilderLoops() }
		/// The strongly connected component of each child in the graph `arrows` describes, and whether each child's component
		/// holds only builders.
		func components(of arrows: [Set<Int>]) -> (componentByIndex: [Int], holdsOnlyBuilders: (Int) -> Bool) {
			let componentByIndex = stronglyConnectedComponents(of: arrows)
			var componentHoldsOnlyBuilders = [Int: Bool]()
			for index in children.indices {
				componentHoldsOnlyBuilders[componentByIndex[index], default: true] = componentHoldsOnlyBuilders[componentByIndex[index], default: true] && isBuilder[index]
			}
			let holdsOnlyBuilders = componentHoldsOnlyBuilders
			return (componentByIndex, { holdsOnlyBuilders[componentByIndex[$0]] == true })
		}
		var arrowsWithEveryCandidate = siblingGraph.dependencies
		for candidate in candidates where candidate.receiver != candidate.sibling {
			arrowsWithEveryCandidate[candidate.receiver].insert(candidate.sibling)
		}
		let candidateComponents = components(of: arrowsWithEveryCandidate)
		// A child's receive of its own property is always given: it closes no circle but the builder's own, which holds only
		// that builder, whatever a receive left `nil` beside it joins the child's component to. Any other candidate is given
		// when its component holds only builders; every other one stays `nil`.
		var givenArrows = siblingGraph.dependencies
		var givenSelfArrows = siblingGraph.childrenRequiringThemselves
		for candidate in candidates
			where candidate.receiver == candidate.sibling
			|| (candidateComponents.componentByIndex[candidate.receiver] == candidateComponents.componentByIndex[candidate.sibling]
				&& candidateComponents.holdsOnlyBuilders(candidate.receiver))
		{
			if candidate.receiver == candidate.sibling {
				givenSelfArrows.insert(candidate.receiver)
			} else {
				givenArrows[candidate.receiver].insert(candidate.sibling)
			}
		}
		// The loops are the components of what is received: the arrows the order keeps and the candidates given. A candidate
		// left `nil` receives nothing, so it never joins a loop of builders, one member included, to a component with a value on
		// it, which would leave its members without the rebindings their functions read.
		let (componentByIndex, isOnLoop) = components(of: givenArrows)
		var loops = ReceivedBuilderLoops()
		for index in children.indices where isOnLoop(index) {
			var reboundProperties = Set<Property>()
			for siblingIndex in givenArrows[index] where componentByIndex[siblingIndex] == componentByIndex[index] {
				if let property = children[siblingIndex].property {
					reboundProperties.insert(property)
				}
			}
			if givenSelfArrows.contains(index), let property = children[index].property {
				reboundProperties.insert(property)
			}
			guard !reboundProperties.isEmpty else { continue }
			loops.reboundPropertiesByChildIndex[index] = reboundProperties
		}
		// A loop's members are the builders of a component that holds only builders and an arrow inside it.
		var componentHoldsArrow = Set<Int>()
		for index in loops.reboundPropertiesByChildIndex.keys {
			componentHoldsArrow.insert(componentByIndex[index])
		}
		var firstMemberByComponent = [Int: Int]()
		for index in children.indices where isOnLoop(index) && componentHoldsArrow.contains(componentByIndex[index]) {
			let firstMember = firstMemberByComponent[componentByIndex[index]] ?? index
			firstMemberByComponent[componentByIndex[index]] = firstMember
			loops.loopByChildIndex[index] = firstMember
		}
		return loops
	}

	/// The lines that make the member calls of builder structs at the top of this scope's builder function, indented for its
	/// body (`memberCallsInsideFunction`).
	nonisolated private var memberCallLines: [String] {
		memberCallsInsideFunction.map { "\(Self.standardIndent)\($0.line(readingInstancesOf: callSiteLazilyInstantiatedInstanceProperties))" }
	}

	/// How this scope spells a `@Sendable` local function it declares (`sendableFunctionsAreNonisolated`).
	nonisolated private var sendableFunctionDecorator: String {
		Self.localFunctionPrefix(isSendable: true, isNonisolated: sendableFunctionsAreNonisolated)
	}

	/// How generated code spells the attributes of a local function it declares: `@Sendable` where the function is, and
	/// `nonisolated` beside it where the code is a seam's that takes a builder struct, or the calling module's code for one,
	/// whose `@Sendable` functions are called from closures no actor isolates.
	static func localFunctionPrefix(isSendable: Bool, isNonisolated: Bool) -> String {
		guard isSendable else { return "" }
		return isNonisolated ? "@Sendable nonisolated " : "@Sendable "
	}

	/// The lines that bind the payloads of the cases on the routes to the places beneath this scope, which its parent emits
	/// before its builder function, where the parent binds their labels: each field read as the parent's receivers read it.
	nonisolated private var valuesBindingLines: String {
		valuesBindings.map { "\($0.line(readingInstancesOf: callSiteLazilyInstantiatedInstanceProperties))\n" }.joined()
	}

	/// The payloads `valuesBindingLines` binds, each as an argument of the initializer of the class a boxed loop's box is
	/// (`boxedLoops`), labeled with its binding's name.
	nonisolated private var valuesBindingArguments: [String] {
		valuesBindings.map { "\($0.bindingName): \($0.expression(readingInstancesOf: callSiteLazilyInstantiatedInstanceProperties))" }
	}

	/// The lines at the top of a boxed loop member's builder function that unbox its own payloads under their names, so
	/// everything beneath reads them as it reads a payload bound before the function.
	nonisolated private func loopLevelsUnboxingLines(from loopLevelsName: String) -> [String] {
		valuesBindings.map { "\(Self.standardIndent)let \($0.bindingName) = \(loopLevelsName).\($0.bindingName)" }
	}

	/// The binding of a boxed loop's box, `name`, an instance of `typeName` made of `arguments`, the payloads of the loop's
	/// members in the order the body generates them (see `boxedLoops`).
	private static func loopLevelsBinding(named name: String, ofType typeName: String, arguments: [String]) -> String {
		var lines = ["let \(name) = \(typeName)("]
		lines.append(arguments.map { "\(standardIndent)\($0)" }.joined(separator: ",\n"))
		lines.append(")")
		return lines.joined(separator: "\n") + "\n"
	}

	/// The private class a boxed loop's box is (`boxedLoops`), which the seam whose tree it is declares beside its
	/// initializers: a local type cannot be declared in a generic context, which a seam's initializer can be, and a type
	/// nested in the seam reaches the generic parameters of an enclosing generic type. Each binding is a stored property of
	/// its own, so that a member's function reads its own in constant time; a tuple held behind a generic parameter was
	/// copied whole on each read, and a walk of the loop grew with its square.
	struct LoopLevelsType {
		/// The class that holds `bindings`, the payloads of a loop's members, in the order the body generates them.
		init(holding bindings: [SeamHoles.ValuesBinding]) {
			// Named after what it holds, so that two loops that hold the same bindings share one declaration, and no other loop
			// of the seam's tree, nor any tier, can declare another class of the name.
			var hash = SeamSignatureHash()
			for binding in bindings {
				hash.combine(binding.bindingName)
				hash.combine(binding.boundType.asSource)
			}
			name = "\(ReservedName.loopLevelsTypeName)_\(hash.hexadecimal)"
			let memberIndent = ScopeGenerator.standardIndent + ScopeGenerator.standardIndent
			var lines = [
				"\(ScopeGenerator.standardIndent)/// Holds the payloads of a loop of builders, so that each builder function of the loop captures one reference.",
				"\(ScopeGenerator.standardIndent)nonisolated private final class \(name) {",
				"\(memberIndent)init(",
			]
			lines.append(bindings.map { "\(memberIndent)\(ScopeGenerator.standardIndent)\($0.bindingName): \($0.boundType.asSource)" }.joined(separator: ",\n"))
			lines.append("\(memberIndent)) {")
			lines += bindings.map { "\(memberIndent)\(ScopeGenerator.standardIndent)self.\($0.bindingName) = \($0.bindingName)" }
			lines += ["\(memberIndent)}", ""]
			lines += bindings.map { "\(memberIndent)let \($0.bindingName): \($0.boundType.asSource)" }
			lines.append("\(ScopeGenerator.standardIndent)}")
			declaration = lines.joined(separator: "\n")
		}

		let name: String
		/// The class's declaration, indented as a member of the seam's extension.
		let declaration: String
	}

	/// The labels two or more of this scope's children declare, each as another property. Only a mock root has any: it
	/// promotes every form its tree receives of a label (`user: User` and `user: Draft`), and names each apart
	/// (`user_User`, `user_Draft`), so no declaration of the label is in scope there.
	nonisolated var labelsChildrenShare: Set<String> {
		var propertyByLabel = [String: Property]()
		var sharedLabels = Set<String>()
		for property in propertiesToGenerate.compactMap(\.property) {
			if let other = propertyByLabel.updateValue(property, forKey: property.label), other != property {
				sharedLabels.insert(property.label)
			}
		}
		return sharedLabels
	}

	/// Whether `child` and `other`, two of this scope's children, are members of one loop of builders (see
	/// `ReceivedBuilderLoops`).
	nonisolated func areMembersOfOneLoop(_ child: ScopeGenerator, _ other: ScopeGenerator) -> Bool {
		guard !receivedBuilderLoops.loopByChildIndex.isEmpty,
		      let childIndex = propertiesToGenerate.firstIndex(where: { $0 === child }),
		      let otherIndex = propertiesToGenerate.firstIndex(where: { $0 === other }),
		      let loop = receivedBuilderLoops.loopByChildIndex[childIndex]
		else { return false }
		return receivedBuilderLoops.loopByChildIndex[otherIndex] == loop
	}

	/// The indices of the children on a loop of builders (see `ReceivedBuilderLoops`) whose wrapper nothing outside their
	/// loop reads: neither this scope's construction nor a generated child that is not on the loop. Only a mock root has any. A
	/// production scope's children are its type's own properties, which its construction reads, while a mock root's are
	/// also the properties it promotes, some only because the tree of a member of their loop receives them.
	nonisolated private func loopMembersReadOnlyInsideTheirLoop() -> [Int] {
		guard case let .root(instantiable, _) = scopeData else { return [] }
		let siblingGraph = Self.siblingGraph(of: propertiesToGenerate, requiredOnlyIfAvailableAliasProperties: requiredOnlyIfAvailableAliasProperties)
		// A child outside a member's loop reads the member's wrapper, and so does a rename this scope declares of it, whose
		// binding is the wrapper under another label, inside the loop or not. Only a generated child reads: a mock root lists
		// a property it instantiates again where a promoted scope receives it, and generates only the first child listing it.
		let firstListingIndices = Set(siblingGraph.siblings.map(\.index))
		var readIndices = Set<Int>()
		for (index, dependencies) in siblingGraph.dependencies.enumerated()
			where firstListingIndices.contains(index) || propertiesToGenerate[index].property == nil
		{
			for dependencyIndex in dependencies
				where propertiesToGenerate[index].isAlias || receivedBuilderLoops.loopByChildIndex[dependencyIndex] != receivedBuilderLoops.loopByChildIndex[index]
			{
				readIndices.insert(dependencyIndex)
			}
		}
		// The construction reads each dependency of its type that it receives or instantiates: the child of that exact
		// property, or, where there is none, the child of its other form. A label the mock root promotes in two forms is
		// read in the form the construction names, so the other form's wrapper is read only where its loop rebinds it.
		let childProperties = Set(propertiesToGenerate.compactMap(\.property))
		var constructionReadProperties = Set<Property>()
		var constructionReadUnwrappedProperties = Set<Property>()
		for dependency in instantiable.dependencies {
			switch dependency.source {
			case .received, .instantiated:
				if childProperties.contains(dependency.property) {
					constructionReadProperties.insert(dependency.property)
				} else {
					constructionReadUnwrappedProperties.insert(dependency.property.asUnwrappedProperty)
				}
			case .aliased, .forwarded:
				continue
			}
		}
		return receivedBuilderLoops.loopByChildIndex.keys.sorted().filter { index in
			!readIndices.contains(index)
				&& !(propertiesToGenerate[index].property.map { constructionReadProperties.contains($0) || constructionReadUnwrappedProperties.contains($0.asUnwrappedProperty) } ?? false)
		}
	}

	/// The strongly connected component of each node of the graph `arrows` describes, each node's arrows by index, named by
	/// the order Tarjan's algorithm finishes them, visiting nodes and arrows in index order. The search keeps its own stack,
	/// since a scope can have as many children receiving one another in turn as the module has types.
	nonisolated static func stronglyConnectedComponents(of arrows: [Set<Int>]) -> [Int] {
		var indexByNode = [Int?](repeating: nil, count: arrows.count)
		var lowLinkByNode = [Int](repeating: 0, count: arrows.count)
		var isOnStack = [Bool](repeating: false, count: arrows.count)
		var componentByNode = [Int](repeating: 0, count: arrows.count)
		var stack = [Int]()
		var nextIndex = 0
		var componentCount = 0
		let sortedArrows = arrows.map { $0.sorted() }
		for startNode in arrows.indices where indexByNode[startNode] == nil {
			var path = [(node: startNode, nextArrowPosition: 0)]
			indexByNode[startNode] = nextIndex
			lowLinkByNode[startNode] = nextIndex
			nextIndex += 1
			stack.append(startNode)
			isOnStack[startNode] = true
			while let (node, arrowPosition) = path.last {
				if arrowPosition < sortedArrows[node].count {
					path[path.count - 1].nextArrowPosition += 1
					let target = sortedArrows[node][arrowPosition]
					if let targetIndex = indexByNode[target] {
						if isOnStack[target] {
							lowLinkByNode[node] = min(lowLinkByNode[node], targetIndex)
						}
					} else {
						indexByNode[target] = nextIndex
						lowLinkByNode[target] = nextIndex
						nextIndex += 1
						stack.append(target)
						isOnStack[target] = true
						path.append((node: target, nextArrowPosition: 0))
					}
				} else {
					path.removeLast()
					if let parent = path.last?.node {
						lowLinkByNode[parent] = min(lowLinkByNode[parent], lowLinkByNode[node])
					}
					if lowLinkByNode[node] == indexByNode[node] {
						var poppedNode: Int?
						repeat {
							poppedNode = stack.popLast()
							if let poppedNode {
								isOnStack[poppedNode] = false
								componentByNode[poppedNode] = componentCount
							}
						} while poppedNode != nil && poppedNode != node
						componentCount += 1
					}
				}
			}
		}
		return componentByNode
	}

	/// Whether a declaration of `declaredProperty` provides a form an `onlyIfAvailable` alias of `fulfillingProperty`
	/// reads (see `Property.formsReadByOnlyIfAvailableReceive`), so the alias is bound from it.
	nonisolated static func provides(_ declaredProperty: Property, aFormReadBy fulfillingProperty: Property) -> Bool {
		let providedForms = CycleParameter.forms(providedBy: declaredProperty)
		return fulfillingProperty.formsReadByOnlyIfAvailableReceive.contains(where: providedForms.contains)
	}

	/// The index in `orderedPropertiesToGenerate` of the last child declaring each
	/// unwrapped property.
	private lazy var orderedIndexByUnwrappedProperty: [Property: Int] = orderedIndexByUnwrappedProperty(orderedIndices: orderedPropertyToGenerateIndices)

	/// `orderedIndexByUnwrappedProperty` for the children ordered as `orderedIndices` says.
	nonisolated private func orderedIndexByUnwrappedProperty(orderedIndices: [Int]) -> [Property: Int] {
		orderedIndices
			.lazy
			.map { self.propertiesToGenerate[$0] }
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
	}

	/// The properties `child`, at `index` in `orderedPropertiesToGenerate`, receives
	/// `onlyIfAvailable` but must treat as unavailable: those this scope's ancestors
	/// do not generate before this scope (`propertiesNotGeneratedBefore`) and those of
	/// the siblings generated after it. All are unwrapped, so they match a receive of
	/// `x: X?`.
	nonisolated private static func propertiesGeneratedLater(
		thanChildAt index: Int,
		receivedOnlyIfAvailableBy child: ScopeGenerator,
		propertiesNotGeneratedBefore: Set<Property>,
		orderedIndexByUnwrappedProperty: [Property: Int],
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
	private lazy var firstOrderedIndexByProperty: [Property: Int] = firstOrderedIndexByProperty(orderedIndices: orderedPropertyToGenerateIndices)

	/// `firstOrderedIndexByProperty` for the children ordered as `orderedIndices` says.
	nonisolated private func firstOrderedIndexByProperty(orderedIndices: [Int]) -> [Property: Int] {
		orderedIndices
			.lazy
			.map { self.propertiesToGenerate[$0] }
			.enumerated()
			.reduce(into: [Property: Int]()) { partialResult, indexAndScope in
				if let property = indexAndScope.element.property, partialResult[property] == nil {
					partialResult[property] = indexAndScope.offset
				}
			}
	}

	/// A child in `orderedPropertiesToGenerate`, with what it is generated with.
	struct OrderedChild {
		let generator: ScopeGenerator
		/// The child's `unavailableProperties`, given the properties this scope generates before it.
		let unavailableProperties: Set<Property>
		/// The `propertiesGeneratedLater` to generate the child with (see `generateCode`).
		let propertiesGeneratedLater: Set<Property>
	}

	/// The children in `orderedPropertiesToGenerate`, each with its `unavailableProperties`
	/// given the properties this scope generates before it, and the `propertiesGeneratedLater`
	/// to generate it with (see `generateCode`). An `onlyIfAvailable` alias is always declared –
	/// bound to `nil` where its fulfilling property is unavailable – so it counts as generated
	/// before the children after it, which read it, `nil` included.
	private func orderedChildren(
		propertiesGeneratedLater: Set<Property>,
	) -> [OrderedChild] {
		orderedChildren(
			propertiesGeneratedLater: propertiesGeneratedLater,
			orderedIndices: orderedPropertyToGenerateIndices,
			orderedIndexByUnwrappedProperty: orderedIndexByUnwrappedProperty,
			firstOrderedIndexByProperty: firstOrderedIndexByProperty,
		)
	}

	/// `orderedChildren(propertiesGeneratedLater:)`, with the order computed afresh, for a walk of a seam's tree
	/// that reads what generation will emit without awaiting each generator.
	nonisolated func orderedChildrenComputedAfresh(propertiesGeneratedLater: Set<Property>) -> [OrderedChild] {
		let orderedIndices = computeOrderedPropertyToGenerateIndices()
		return orderedChildren(
			propertiesGeneratedLater: propertiesGeneratedLater,
			orderedIndices: orderedIndices,
			orderedIndexByUnwrappedProperty: orderedIndexByUnwrappedProperty(orderedIndices: orderedIndices),
			firstOrderedIndexByProperty: firstOrderedIndexByProperty(orderedIndices: orderedIndices),
		)
	}

	nonisolated private func orderedChildren(
		propertiesGeneratedLater: Set<Property>,
		orderedIndices: [Int],
		orderedIndexByUnwrappedProperty: [Property: Int],
		firstOrderedIndexByProperty: [Property: Int],
	) -> [OrderedChild] {
		let propertiesNotGeneratedBefore = propertiesGeneratedLater
		var orderedChildren = [OrderedChild]()
		for (index, childGenerator) in orderedIndices.lazy.map({ self.propertiesToGenerate[$0] }).enumerated() {
			let childPropertiesGeneratedLater = Self.propertiesGeneratedLater(
				thanChildAt: index,
				receivedOnlyIfAvailableBy: childGenerator,
				propertiesNotGeneratedBefore: propertiesNotGeneratedBefore,
				orderedIndexByUnwrappedProperty: orderedIndexByUnwrappedProperty,
			)
			// A property is generated before the child when a child ordered before it declares the property.
			let childUnavailableProperties = childGenerator.unavailableProperties(
				isGeneratedBefore: { property in
					firstOrderedIndexByProperty[property].map { $0 < index } == true
				},
				propertiesGeneratedLater: childPropertiesGeneratedLater,
			)
			orderedChildren.append(OrderedChild(
				generator: childGenerator,
				unavailableProperties: childUnavailableProperties,
				propertiesGeneratedLater: childPropertiesGeneratedLater,
			))
		}
		return orderedChildren
	}

	/// The dependencies this scope's construction is passed `nil` for, and, for an
	/// alias, the fulfilling property whose absence means the alias is bound to `nil`:
	/// the `onlyIfAvailable` dependencies `Scope.createScopeGenerator` found
	/// unavailable that no sibling generated before this scope provides, and those
	/// an enclosing scope does not generate before this scope.
	/// - Parameter isGeneratedBefore: Whether a sibling generated before this scope declares a property.
	nonisolated private func unavailableProperties(
		isGeneratedBefore: (Property) -> Bool,
		propertiesGeneratedLater: Set<Property>,
	) -> Set<Property> {
		// The parameters of a builder function a lazy cycle closes on that this scope passes `nil` are unavailable here.
		let unavailableOptionalPropertiesNotGeneratedBefore = (cycleParameterUnavailableProperties.isEmpty ? unavailableOptionalProperties : unavailableOptionalProperties.union(cycleParameterUnavailableProperties))
			.filter {
				!(isGeneratedBefore($0) || isGeneratedBefore($0.asUnwrappedProperty))
			}
		// Nearly every scope is generated with no properties generated later.
		return propertiesGeneratedLater.isEmpty
			? unavailableOptionalPropertiesNotGeneratedBefore
			: unavailableOptionalPropertiesNotGeneratedBefore.union(onlyIfAvailableDependencies(fulfilledByPropertiesGeneratedLater: propertiesGeneratedLater))
	}

	/// Whether an alias – `onlyIfAvailable` or not, bound from `fulfillingProperty` – is bound to `nil`: an
	/// `onlyIfAvailable` alias is when its fulfilling property is among `unavailableProperties`. Asked of an alias's
	/// scope data alone, which each caller has matched.
	static func aliasIsBoundToNil(onlyIfAvailable: Bool, fulfillingProperty: Property, unavailableProperties: Set<Property>) -> Bool {
		onlyIfAvailable && unavailableProperties.contains(fulfillingProperty)
	}

	/// The first receive of each of `labels` – labels the body of the builder function of the scope that builds
	/// `builtType` for `builtProperty`, the declaration `builtDeclaration`, receives from the scopes enclosing it, each with
	/// a value that is returned beside it (for a cycle parameter, its label's declaration between the function and one of
	/// its cycle-closing scopes) – in the
	/// order a walk of the body meets them: the type's own dependencies, `ownDependencies`, then each of `children`'s
	/// trees, depth first, each scope's dependencies (and a cycle-closing scope's parameters, which it receives for the
	/// function it refers to, where that function's body first receives them) before its children's, all in declaration
	/// order. The order depends only on where the labels are received, never on how they or their types are named, so
	/// renaming a graph never reorders a function's parameters. Every label the body receives is met: a receive comes
	/// from a dependency of a type the walk visits, an alias among the dependencies of the type declaring it, which the
	/// walk visits first, or a cycle-closing scope's parameter.
	private static func inOrderTheBodyFirstReceives<Value>(
		ofLabels labels: [String: Value],
		builtProperty: Property,
		builtDeclaration: BuiltDeclaration,
		builtType: TypeDescription,
		ownDependencies: [Dependency],
		children: [ScopeGenerator],
	) -> [(label: String, receiver: CycleParameter.Receiver, value: Value)] {
		var unmetLabels = labels
		var firstReceives = [(label: String, receiver: CycleParameter.Receiver, value: Value)]()
		// The types the walk visits, each with the index of the type it is built inside, so that a receiver's chain is
		// spelled only for the receives the walk meets first.
		var visitedTypes: [(type: TypeDescription, parentIndex: Int?)] = [(builtType, nil)]
		/// The types from `builtType` to the one at `index` in `visitedTypes`, both included.
		func chain(endingAt index: Int) -> [TypeDescription] {
			var chain = [TypeDescription]()
			var nextIndex: Int? = index
			while let index = nextIndex {
				chain.append(visitedTypes[index].type)
				nextIndex = visitedTypes[index].parentIndex
			}
			return chain.reversed()
		}
		func meet(_ label: String, receiver: @autoclosure () -> CycleParameter.Receiver) {
			if let value = unmetLabels.removeValue(forKey: label) {
				firstReceives.append((label, receiver(), value))
			}
		}
		/// Meets the receives among `dependencies`, those of the type at `index` in `visitedTypes`.
		func meet(_ dependencies: [Dependency], ofTypeAt index: Int) {
			// Read only for a type with an alias, which few are.
			var ownDeclaredProperties: Set<Property>?
			for dependency in dependencies {
				switch dependency.source {
				case .received:
					meet(dependency.property.label, receiver: .init(property: dependency.property, declarationLocation: dependency.declarationLocation, chain: chain(endingAt: index)))
				case let .aliased(fulfillingProperty, _, onlyIfAvailable):
					// An alias of a property its own type declares reads that declaration, also where a cycle-closing scope
					// calls the type's builder function, which binds its own: it receives nothing.
					let declaredProperties = ownDeclaredProperties ?? propertiesDeclared(byOwnDependencies: dependencies)
					ownDeclaredProperties = declaredProperties
					guard !declaresFulfillingProperty(
						of: fulfillingProperty,
						onlyIfAvailable: onlyIfAvailable,
						declaredProperties: declaredProperties,
						forwardedProperties: [],
					) else { continue }
					meet(fulfillingProperty.label, receiver: .init(property: fulfillingProperty, declarationLocation: dependency.declarationLocation, chain: chain(endingAt: index)))
				case .instantiated, .forwarded:
					continue
				}
			}
		}
		meet(ownDependencies, ofTypeAt: 0)
		// The scope visited next is the last one on the stack, so the first child goes last. Each is visited with the index
		// of the type it is built inside.
		var generatorsToVisit = children.reversed().map { (generator: $0, parentIndex: 0) }
		while !unmetLabels.isEmpty, let (generator, parentIndex) = generatorsToVisit.popLast() {
			// An alias is among the dependencies of the type that declares it, which the walk met first.
			var index = parentIndex
			if let builtInstantiable = generator.builtInstantiable {
				visitedTypes.append((builtInstantiable.concreteInstantiable, parentIndex))
				index = visitedTypes.count - 1
				meet(builtInstantiable.dependencies, ofTypeAt: index)
			}
			// A cycle-closing scope receives the parameters of the function it refers to, where that function's body does.
			for parameter in generator.cycleParameters where generator.closesPropertyCycle {
				// This function's own parameter, whose receive this walk met where the scope was given the parameter: a chain
				// through the scope would grow with each pass that finds the parameters, which then never settle. A scope
				// closes on this function when it repeats its declaration, in either form: a lazily instantiated scope repeats a
				// constant declaration of its label and instance type, and a constant scope a lazily instantiated one, while
				// their properties differ. A scope of this function's property that closes on a function built for another
				// concrete type keeps the receiver it was given too; a chain through it would change only diagnostic text.
				meet(parameter.property.label, receiver: generator.property == builtProperty || generator.closedOnDeclaration == builtDeclaration
					? parameter.receiver
					: .init(property: parameter.receiver.property, declarationLocation: parameter.receiver.declarationLocation, chain: chain(endingAt: parentIndex) + parameter.receiver.chain))
			}
			generatorsToVisit.append(contentsOf: generator.propertiesToGenerate.reversed().map { (generator: $0, parentIndex: index) })
		}
		return firstReceives
	}

	/// Whether this scope declares a builder function a lazy cycle closes on that takes parameters (see `CycleParameter`).
	nonisolated var declaresCycleParameters: Bool {
		!cycleParameters.isEmpty && !closesPropertyCycle
	}

	/// `declarationsByLabel`, the declarations a walk of omissions (see `OmissionFindings`) sees where this scope's builder
	/// function, `function`, is declared, as the function's body sees them: each parameter's label names the parameter.
	nonisolated private func bodyDeclarations(function: ObjectIdentifier, enclosing declarationsByLabel: [String: [VisibleDeclaration]]) -> [String: [VisibleDeclaration]] {
		guard declaresCycleParameters else { return declarationsByLabel }
		var bodyDeclarationsByLabel = declarationsByLabel
		for parameter in cycleParameters {
			bodyDeclarationsByLabel[parameter.property.label] = [VisibleDeclaration(
				property: parameter.property,
				instanceProperty: parameter.property.asLazilyInstantiatedInstancePropertyOfDeclaredBinding,
				declaringType: nil,
				declarationLocation: nil,
				sendableBuilderDepth: 0,
				cycleFunction: function,
			)]
		}
		return bodyDeclarationsByLabel
	}

	/// `enclosingCycleFunctions`, the builder functions that take parameters a lazy cycle needs and enclose where this
	/// scope's builder function, `function`, which builds its `declaration`, is declared, as the function's body sees them.
	nonisolated private func bodyEnclosingCycleFunctions(function: ObjectIdentifier, enclosing enclosingCycleFunctions: [BuiltDeclaration: ObjectIdentifier]) -> [BuiltDeclaration: ObjectIdentifier] {
		guard declaresCycleParameters, let declaration else { return enclosingCycleFunctions }
		var bodyEnclosingCycleFunctions = enclosingCycleFunctions
		bodyEnclosingCycleFunctions[declaration] = function
		return bodyEnclosingCycleFunctions
	}

	/// The forms the parameters of this scope's builder function provide to the function's body, or none when it takes
	/// no parameters a lazy cycle needs.
	nonisolated private var cycleParameterProvidedForms: Set<Property> {
		declaresCycleParameters ? Set(cycleParameters.flatMap(\.providedForms)) : []
	}

	/// The properties this scope's type is passed `nil` for where its builder function constructs it, given
	/// `unavailableProperties`, which are unavailable where the function is called: the forms the function's parameters
	/// provide are bound inside it, whatever the scope calling it passes.
	nonisolated private func bodyUnavailableProperties(_ unavailableProperties: Set<Property>) -> Set<Property> {
		let bodyProvidedForms = bodyProvidedForms
		return bodyProvidedForms.isEmpty ? unavailableProperties : unavailableProperties.subtracting(bodyProvidedForms)
	}

	/// The forms the body of this scope's builder function binds before anything in it reads them: those its parameters
	/// that a lazy cycle needs provide, and those of the properties it rebinds as a member of a loop of builders (see
	/// `ReceivedBuilderLoops`). Empty for nearly every scope.
	nonisolated private var bodyProvidedForms: Set<Property> {
		guard !reboundProperties.isEmpty else { return cycleParameterProvidedForms }
		var bodyProvidedForms = cycleParameterProvidedForms
		for reboundProperty in reboundProperties {
			bodyProvidedForms.formUnion(CycleParameter.forms(providedBy: reboundProperty))
		}
		return bodyProvidedForms
	}

	/// The `propertiesGeneratedLater` of the scopes this scope's builder function builds, given those of this scope: the
	/// forms the function's parameters provide are bound inside it.
	nonisolated private func bodyPropertiesGeneratedLater(_ propertiesGeneratedLater: Set<Property>) -> Set<Property> {
		guard declaresCycleParameters || !reboundProperties.isEmpty, !propertiesGeneratedLater.isEmpty else { return propertiesGeneratedLater }
		return propertiesGeneratedLater.subtracting(bodyProvidedForms.map(\.asUnwrappedProperty))
	}

	/// The name of the builder function this scope, which closes a property cycle on `closedOnDeclaration` and is built for
	/// `property`, calls or hands its wrapper: the function of the declaration it repeats, as the scopes enclosing it named
	/// it. The two properties share a label, which the function is named after unless a rename moved it.
	///
	/// In a mock's body, that function reads the level member of a builder the mock bound where the level first opened, so a
	/// level that reopens hands a builder passed up to the mock's caller the first opening's values, until loops re-enter per
	/// opening; a generated fill that reads a label the loop declares again is rejected (`declarationBoundOnCycleReentry`).
	nonisolated private func closedOnFunctionName(builtFor property: Property, enclosingFunctionNames: [BuiltDeclaration: String]) -> String {
		closedOnDeclaration.flatMap { enclosingFunctionNames[$0] } ?? Self.functionName(toBuild: property)
	}

	/// The arguments this scope passes the builder function a lazy cycle closes on, labeled by parameter: the binding of
	/// each label in scope here – a lazily instantiated property's instance where the parameter takes it by value – or
	/// `nil` where it is unavailable.
	nonisolated private func cycleParameterArguments(unavailableProperties: Set<Property>) -> [String] {
		cycleParameters.map { parameter in
			let label = parameter.property.label
			let source: ArgumentSource = if unavailableProperties.contains(parameter.property) {
				.nil
			} else if let instanceSource = callSiteLazilyInstantiatedInstanceProperties.lazilyInstantiatedInstanceSource(of: parameter.property, boundAs: label) {
				// A deliberate gap: reading the instance here creates it when the function is called, not when a receiver in
				// the function's body first reads it. Mock generation does the same (`mockCycleParameterArguments`). See
				// "Eager instances at a lazy cycle's calls" in `.claude/rules/cycle-generation.md`. Beneath a fill that takes the
				// wrapper optionally, the instance is read through the optional.
				instanceSource
			} else {
				.binding(label: label)
			}
			return CallArgument(label: label, source: source).spelled
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

	/// - Parameters:
	///   - enclosingFunctionNames: This scope's `BuilderFunctionNames.enclosingFunctionNames`.
	///   - fillPlaceBindings: The bindings of the places inside the fills an internal mock declares, which every scope of
	///     a fill's tree emits in its builder function.
	private func generateProperties(
		codeGeneration: CodeGeneration = .dependencyTree,
		propertiesGeneratedLater: Set<Property>,
		enclosingFunctionNames: [BuiltDeclaration: String],
		leadingMemberWhitespace: String,
		fillPlaceBindings: FillPlaceBindings,
	) async throws -> [GeneratedCode] {
		// Only each child's code is awaited here: what the body decides around it is decided by the synchronous functions
		// below, as a property's scope is (`generatePropertyCode`).
		var body = bodyChildren(propertiesGeneratedLater: propertiesGeneratedLater, enclosingFunctionNames: enclosingFunctionNames)
		for index in body.orderedChildren.indices where body.orderedChildren[index].generator.fillEmitsCode {
			let code = try await body.orderedChildren[index].generator.generateCode(
				codeGeneration: codeGeneration,
				unavailableProperties: body.orderedChildren[index].unavailableProperties,
				propertiesGeneratedLater: body.orderedChildren[index].propertiesGeneratedLater,
				builderFunctionNames: builderFunctionNamesOfChild(at: index, in: body),
				leadingWhitespace: leadingMemberWhitespace,
				fillPlaceBindings: fillPlaceBindings,
			)
			append(code, ofChildAt: index, to: &body, leadingMemberWhitespace: leadingMemberWhitespace, fillPlaceBindings: fillPlaceBindings)
		}
		return statements(of: consume body, leadingMemberWhitespace: leadingMemberWhitespace)
	}

	/// What a body decides of its children before it awaits their code, and what it has written of them since: the
	/// statements of the children it does not inline, and the bodies of the fills it does.
	private struct BodyChildren {
		/// The children in the order the body generates them.
		let orderedChildren: [OrderedChild]
		/// The builder function names of each child, in that order, where they are not the children's own; `nil` where
		/// every child keeps its own.
		let childBuilderFunctionNames: [BuilderFunctionNames?]?
		/// Per loop of builders: the rebinding of each member the body declares, wrapping the function this body names.
		let loopMemberDeclarationsByLoop: [Int: [Property: String]]
		/// The `_received` function of each member, by its index among `orderedChildren`, that takes cycle parameters.
		let receivedFunctionNameByIndex: [Int: String]
		/// Per loop: the lines binding its members' payloads, the index of the member that binds them, and the name of a
		/// boxed loop's box.
		let valuesBindingLinesByLoop: [Int: String]
		let valuesBindingMemberIndexByLoop: [Int: Int]
		let loopLevelsNameByLoop: [Int: String]
		/// The fills an override closure of the call is handed a function over.
		let overrideFillKeys: Set<String>
		/// The fills a level function's member hands each field of its payload they read, rather than the payload.
		let fillsTakingPayloadFields: Set<String>
		/// What each fill nested by type takes beside its case's payload.
		let fillParametersByKey: [String: [SeamSignature.Hole.Field]]
		/// What each fill and each dispatcher takes.
		let parametersByKey: [String: [SeamSignature.Hole.Field]]
		/// What the root dispatcher passes of each value it reads from this scope, by the parameter a target takes for it,
		/// and of each memo.
		let callerArgumentByParameter: [Property: String]
		let callerMemoArgumentByMemo: [Property: String]
		/// The dispatchers of a seam's caller; empty for a public mock's caller, which declares level functions instead.
		let callDispatchers: [FillDispatcher]
		/// Which fills a dispatcher may hold in its case.
		let fillInlining: FillInlining
		/// The children's statements so far, in order, but for the fills a dispatcher holds.
		var generatedProperties = [GeneratedCode]()
		/// The bodies of the fills a dispatcher holds, by fill.
		var inlinedFills = [String: FillDispatcher.InlinedFill]()
	}

	// `generateProperties` awaits each child's code between the synchronous functions below, for the reason
	// `generatePropertyCode` gives: each is kept out of the async function (`@inline(never)`).

	/// What the body decides of its children before it awaits their code.
	@inline(never)
	private func bodyChildren(propertiesGeneratedLater: Set<Property>, enclosingFunctionNames: [BuiltDeclaration: String]) -> BodyChildren {
		let orderedChildren = orderedChildren(propertiesGeneratedLater: propertiesGeneratedLater)
		// Nearly every body holds no scope of a cycle, and its children keep their names. Every child but a seam
		// call's fill is a property's scope, so each has a candidate; a fill keeps the name it was constructed with.
		let childBuilderFunctionNames: [BuilderFunctionNames?]? = if childrenTakePartInCycle || orderedChildren.contains(where: { !$0.generator.referencedFillNamesByKey.isEmpty }) {
			{
				let candidates = orderedChildren.map(\.generator.builderFunctionCandidate)
				var names = Self.builderFunctionNames(
					for: candidates.compactMap(\.self),
					enclosingFunctionNames: enclosingFunctionNames,
				).makeIterator()
				return candidates.map { $0 == nil ? nil : names.next() }
			}()
		} else {
			nil
		}
		// Each member of a loop of builders rebinds the members its tree receives inside the loop as this body declares them,
		// wrapping the functions this body names. A member whose function takes parameters a lazy cycle needs – a member
		// that declares such a function, or a cycle-closing scope that calls one – is wrapped through a function of no
		// such parameters, `__safeDI_<label>_received`, that this body declares beside it and that passes the parameters
		// what this body binds, a member of the same loop as a wrapper the function makes. Nearly every body holds no loop.
		var loopMemberDeclarationsByLoop = [Int: [Property: String]]()
		var receivedFunctionNameByIndex = [Int: String]()
		var memberFunctionByProperty = [Property: (property: Property, generator: ScopeGenerator, functionName: String)]()
		// The payloads of each loop's members, in the order the body generates them, and the index of the member that binds
		// them all: the loop's first. A boxed loop (`boxedLoops`) binds them in its box, named in `loopLevelsNameByLoop`.
		var valuesBindingLinesByLoop = [Int: String]()
		var valuesBindingMemberIndexByLoop = [Int: Int]()
		var boxedArgumentsByLoop = [Int: [String]]()
		var loopLevelsNameByLoop = [Int: String]()
		if !receivedBuilderLoops.loopByChildIndex.isEmpty {
			let loopByGenerator = Dictionary(
				receivedBuilderLoops.loopByChildIndex.map { (ObjectIdentifier(propertiesToGenerate[$0.key]), $0.value) },
				uniquingKeysWith: { first, _ in first },
			)
			for (index, child) in orderedChildren.enumerated() where !child.generator.isAlias {
				guard let loop = loopByGenerator[ObjectIdentifier(child.generator)] else { continue }
				if boxedLoops[loop] != nil {
					boxedArgumentsByLoop[loop, default: []] += child.generator.valuesBindingArguments
				} else {
					valuesBindingLinesByLoop[loop, default: ""] += child.generator.valuesBindingLines
				}
				if valuesBindingMemberIndexByLoop[loop] == nil {
					valuesBindingMemberIndexByLoop[loop] = index
				}
			}
			// A `__safeDI_<label>_received` function is named apart, with underscores appended, from every name in scope
			// where it is declared or read (see `namesReceivedFunctionsAvoid`).
			var names = LoopMemberNames(reserving: namesReceivedFunctionsAvoid(
				orderedChildren: orderedChildren,
				childBuilderFunctionNames: childBuilderFunctionNames,
				loopMembers: orderedChildren.compactMap { loopByGenerator[ObjectIdentifier($0.generator)] == nil ? nil : $0.generator },
				enclosingFunctionNames: enclosingFunctionNames,
			))
			for (index, child) in orderedChildren.enumerated() where !child.generator.isAlias {
				guard let property = child.generator.property, let loop = loopByGenerator[ObjectIdentifier(child.generator)] else { continue }
				let childBuilderFunctionNames = childBuilderFunctionNames?[index] ?? nil
				var functionName = if child.generator.closesPropertyCycle {
					child.generator.closedOnFunctionName(builtFor: property, enclosingFunctionNames: childBuilderFunctionNames?.enclosingFunctionNames ?? [:])
				} else {
					childBuilderFunctionNames?.functionName ?? Self.functionName(toBuild: property)
				}
				// A boxed loop's box is named after its first member's builder function, apart from every name in scope as a
				// `_received` function is, and bound where the loop's payloads were. A public mock's loop binds each payload in a
				// `let` of its own – in its body (`InstantiatorBindingLines.prelude`) and in its fills, which this function
				// generates (`SeamHoles.holdsLoopPayloadsInBoxes`) – a deliberate gap: a public mock's payloads were never builder
				// structs, so its loops capture what they captured before.
				let box = boxedLoops[loop].flatMap { typeName in boxedArgumentsByLoop[loop].map { (typeName: typeName, arguments: $0) } }
				let claimedNames = names.claim(
					forMemberBuiltBy: functionName,
					bindsLoopsBox: box != nil && valuesBindingMemberIndexByLoop[loop] == index,
					takesCycleParameters: !child.generator.cycleParameters.isEmpty,
				)
				if let loopLevelsName = claimedNames.loopLevelsName, let box {
					loopLevelsNameByLoop[loop] = loopLevelsName
					valuesBindingLinesByLoop[loop] = Self.loopLevelsBinding(named: loopLevelsName, ofType: box.typeName, arguments: box.arguments)
				}
				if let receivedFunctionName = claimedNames.receivedFunctionName {
					functionName = receivedFunctionName
					receivedFunctionNameByIndex[index] = functionName
				}
				loopMemberDeclarationsByLoop[loop, default: [:]][property] = child.generator.loopRebindingDeclaration(functionName: functionName)
				memberFunctionByProperty[property] = (property, child.generator, functionName)
			}
			// A rename this body declares of a member is rebound under its own label, wrapping the member's function.
			for child in orderedChildren where child.generator.isAlias {
				guard case let .alias(property, fulfillingProperty, _, _, _) = child.generator.scopeData,
				      let loop = loopByGenerator[ObjectIdentifier(child.generator)],
				      let memberFunction = memberFunctionByProperty[fulfillingProperty],
				      let declaration = child.generator.loopRebindingDeclaration(ofRenameOf: memberFunction)
				else { continue }
				loopMemberDeclarationsByLoop[loop, default: [:]][property] = declaration
			}
		}
		// What each fill nested by type takes beside its case's payload, then what each dispatcher takes to pass on.
		var fillParametersByKey = [String: [SeamSignature.Hole.Field]]()
		// What the root dispatcher passes of each value it reads from this scope, by the parameter a target takes for it: the
		// caller's declaration in that parameter's form, or `nil` where a fill reads it only if available and this scope
		// declares none, or builds it later. Two fills that take one label in different forms are each handed their own form.
		// The caller's declaration in one form is the same for every fill of the call, which reads the one scope enclosing it
		// (`Scope.Fill.callerNearestDeclarations`), so nothing is chosen among spellings: a form is passed as the declaration
		// where any fill that takes it finds it available, and as `nil` where none does.
		var callerArgumentByParameter = [Property: String]()
		var callerMemoArgumentByMemo = [Property: String]()
		// The fills a level function's member hands each field of its payload they read, rather than the payload: those that
		// return a wrapper's builder, and those an override closure of the call is handed a function over, which the closure
		// calls with the caller's values.
		var fillsTakingPayloadFields = Set<String>()
		var overrideFillKeys = Set<String>()
		for builder in (publicMockOverrideBuilders ?? [:]).values {
			if case let .fill(key, _, _, _, _) = builder {
				overrideFillKeys.insert(key)
			}
		}
		if !fillDispatchers.isEmpty {
			for child in orderedChildren {
				if let key = child.generator.fillKey, child.generator.fillEmitsCode {
					let takesPayloadFields = child.generator.fillReturnsWrapperBuilder || overrideFillKeys.contains(key)
					fillParametersByKey[key] = child.generator.fillMemberParameterFields(takingPayloadFields: takesPayloadFields)
					if takesPayloadFields {
						fillsTakingPayloadFields.insert(key)
					}
					let callerReads = child.generator.fillCallerReads
					for (label, argument) in callerReads.argumentByLabel {
						guard let parameter = callerReads.parameterByLabel[label]?.property else { continue }
						let forms = callerReads.dependencies.map(\.property).filter { $0.label == label }
						if !forms.allSatisfy(child.unavailableProperties.contains) {
							callerArgumentByParameter[parameter] = argument
						} else if callerArgumentByParameter[parameter] == nil {
							callerArgumentByParameter[parameter] = "nil"
						}
					}
					callerMemoArgumentByMemo.merge(callerReads.memoArgumentByMemo) { argument, _ in argument }
				}
			}
		}
		// A case of this call's that leads to a level function an enclosing call declares hands it this call's struct of the type
		// of each struct it takes, in its order: what that function reads is found in the enclosing call, so this call reads it
		// here, and the level functions on the way to it take those structs in turn.
		for dispatcher in fillDispatchers {
			for target in dispatcher.cases.compactMap(\.target) where !target.reusedCarriedInnerScopes.isEmpty {
				fillParametersByKey[target.key] = target.reusedCarriedInnerScopes.compactMap { reused in
					dispatcher.carriedInnerScopes.first { $0.type == reused.type }.map { carried in
						SeamSignature.Hole.Field(property: Property(label: carried.name, typeDescription: carried.type), access: .public, declaringType: carried.type, declarationLocation: nil)
					}
				}
			}
		}
		// A public mock's caller declares level functions of its own (`PublicMockLevelFunctions`); a seam's caller its
		// dispatchers, each value handed on per label (`dispatcherParameters(of:fillReads:)`).
		let callDispatchers = publicMockLevelFunctions == nil ? fillDispatchers : []
		let dispatcherParametersByKey = FillDispatcher.dispatcherParameters(of: callDispatchers, fillReads: fillParametersByKey)
		return BodyChildren(
			orderedChildren: orderedChildren,
			childBuilderFunctionNames: childBuilderFunctionNames,
			loopMemberDeclarationsByLoop: loopMemberDeclarationsByLoop,
			receivedFunctionNameByIndex: receivedFunctionNameByIndex,
			valuesBindingLinesByLoop: valuesBindingLinesByLoop,
			valuesBindingMemberIndexByLoop: valuesBindingMemberIndexByLoop,
			loopLevelsNameByLoop: loopLevelsNameByLoop,
			overrideFillKeys: overrideFillKeys,
			fillsTakingPayloadFields: fillsTakingPayloadFields,
			fillParametersByKey: fillParametersByKey,
			parametersByKey: fillParametersByKey.merging(dispatcherParametersByKey) { fillParameters, _ in fillParameters },
			callerArgumentByParameter: callerArgumentByParameter,
			callerMemoArgumentByMemo: callerMemoArgumentByMemo,
			callDispatchers: callDispatchers,
			// A public mock's level function holds the body of a fill it hands each value in the form the fill takes it, under
			// its own label, and declares no function inside the closure its struct stores.
			fillInlining: FillInlining(
				inlinableFillKeys: inlinableFillKeys,
				publicMockInlinableFillKeys: publicMockLevelFunctions?.keysOfFillsCalledWithOwnValues,
				overrideFillKeys: overrideFillKeys,
				keysTargetedByBuilderStructDispatchers: Set(callDispatchers.filter(\.returnsBuilderStruct).flatMap { $0.cases.compactMap(\.target?.key) }),
			),
		)
	}

	/// The names the code of the child at `index` among `body`'s ordered children refers to builder functions by.
	@inline(never)
	private func builderFunctionNamesOfChild(at index: Int, in body: BodyChildren) -> BuilderFunctionNames {
		let child = body.orderedChildren[index]
		var builderFunctionNames = body.childBuilderFunctionNames?[index].flatMap(\.self)
			?? BuilderFunctionNames(fillIsSendable: buildsInSendableFunction(ofFill: child.generator))
		builderFunctionNames.fillTakesPayloadFields = child.generator.fillKey.map(body.overrideFillKeys.contains) ?? false
		if !body.loopMemberDeclarationsByLoop.isEmpty,
		   let childIndex = propertiesToGenerate.firstIndex(where: { $0 === child.generator }),
		   let loop = receivedBuilderLoops.loopByChildIndex[childIndex]
		{
			builderFunctionNames.loopMemberDeclarations = body.loopMemberDeclarationsByLoop[loop, default: [:]]
			builderFunctionNames.receivedFunctionName = body.receivedFunctionNameByIndex[index]
			if !child.generator.isAlias {
				builderFunctionNames.loopValuesBindingLines = body.valuesBindingMemberIndexByLoop[loop] == index ? body.valuesBindingLinesByLoop[loop, default: ""] : ""
				builderFunctionNames.loopLevelsName = body.loopLevelsNameByLoop[loop]
			}
		}
		return builderFunctionNames
	}

	/// Adds `code`, the code of the child at `index` among `body`'s ordered children, to what `body` has written: as the
	/// body of a fill a dispatcher holds, or as a statement of its own.
	@inline(never)
	private func append(_ code: GeneratedCode, ofChildAt index: Int, to body: inout BodyChildren, leadingMemberWhitespace: String, fillPlaceBindings: FillPlaceBindings) {
		let child = body.orderedChildren[index]
		if let key = child.generator.fillKey,
		   body.fillInlining.mayHold(key),
		   // A fill is hosted as its text until fills are planned (`.claude/rules/emission-decisions.md`).
		   let inlinedFill = Self.inlinedFill(of: child.generator, code: code.spelled(), leadingMemberWhitespace: leadingMemberWhitespace),
		   !body.fillInlining.keepsFunction(key, declaresFunction: child.generator.fillDeclaresFunction(fillPlaceBindings: fillPlaceBindings))
		{
			body.inlinedFills[key] = inlinedFill
		} else {
			body.generatedProperties.append(code)
		}
	}

	/// The statements of `body`, its children's code followed by the declarations of its call's dispatchers or a public
	/// mock's level functions.
	@inline(never)
	private func statements(of body: consuming BodyChildren, leadingMemberWhitespace: String) -> [GeneratedCode] {
		// Moved out of `body`, so that appending to it does not copy it.
		var generatedProperties = [GeneratedCode]()
		swap(&generatedProperties, &body.generatedProperties)
		// A call's dispatchers follow its fills, each a function that returns its level's struct.
		for dispatcher in body.callDispatchers {
			generatedProperties.append(.text(dispatcher.declaration(
				isSendable: sendableFillKeys.contains(dispatcher.key),
				indent: leadingMemberWhitespace,
				inlinedFills: body.inlinedFills,
				parametersByKey: body.parametersByKey,
				callerArgumentByParameter: body.callerArgumentByParameter,
				callerMemoArgumentByMemo: body.callerMemoArgumentByMemo,
				typesDeclaredEscaping: typesDeclaredEscaping,
				fillsTakingPayloadFields: body.fillsTakingPayloadFields,
				labelsHiddenByReenteringCalls: Set(fillDeferredLabelsHiddenByReenteringCalls.values.joined()),
			)))
		}
		if let publicMockLevelFunctions {
			generatedProperties += publicMockLevelFunctions.declarations(
				indent: leadingMemberWhitespace,
				sendableKeys: sendableFillKeys,
				inlinedFills: body.inlinedFills,
				fillsTakingPayloadFields: body.fillsTakingPayloadFields,
				fillMemberParameterFieldsByKey: body.fillParametersByKey,
				typesDeclaredEscaping: typesDeclaredEscaping,
			).map(GeneratedCode.text)
		}
		return generatedProperties
	}

	/// What this scope's call of another module's public mock passes each builder, by label: the call of the builder's root
	/// level function (`PublicMockLevelFunctions.rootCallsByLabel`), or the struct the caller passes up where the call fills
	/// no place of the builder.
	nonisolated var publicMockBuilderStructValuesByLabel: [String: String] {
		var valuesByLabel = [String: String]()
		for builderCallArgument in builderCallArguments {
			guard let builderStruct = builderCallArgument.builderStruct else { continue }
			valuesByLabel[builderCallArgument.label] = publicMockLevelFunctions?.rootCallsByLabel[builderCallArgument.label] ?? builderStruct.upValue
		}
		return valuesByLabel
	}

	/// The body of `fill`, whose function is `code` indented by `leadingMemberWhitespace`, as the dispatcher case that calls
	/// it holds it: the function's body under the names the case binds. `nil` for a fill whose scope parameter is named
	/// apart, because its place carries a field or its tree reads a value labeled `scope`, which the dispatcher's own
	/// parameter would hide: it keeps its function.
	private static func inlinedFill(of fill: ScopeGenerator, code: String, leadingMemberWhitespace: String) -> FillDispatcher.InlinedFill? {
		// A fill is its function's declaration, its body, and the line closing it.
		let lines = code.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
		let carriesPayload = fill.fillHole?.valuesType(qualifiedBy: nil) != nil
		guard lines.count > 2,
		      !carriesPayload || lines[0].contains("(_ scope: "),
		      lines[lines.count - 1] == leadingMemberWhitespace + "}"
		else { return nil }
		let body = lines[1..<(lines.count - 1)].map { Self.standardIndent + $0 }
		// The fill binds the fields its tree reads first, each from the scope; nothing after them reads the scope.
		let readsScope = carriesPayload && lines[1].hasPrefix(leadingMemberWhitespace + Self.standardIndent + "let ") && lines[1].contains(" = scope.")
		let builtProperty = fill.propertiesToGenerate.first?.property
		let forwardedValueName = fill.fillHole?.forwardedType == nil ? nil : builtProperty.map(Self.forwardedValueParameterName(forBuilding:))
		let readsForwardedValue = forwardedValueName.map { name in
			body.contains { line in
				line.split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "_") }).contains(Substring(name))
			}
		} ?? false
		return FillDispatcher.InlinedFill(
			carriesPayload: carriesPayload,
			readsScope: readsScope,
			forwardedValueName: forwardedValueName,
			readsForwardedValue: readsForwardedValue,
			body: body,
		)
	}

	/// Whether this fill's body declares a function: the builder function of the property it fills, which a wrapper, a
	/// constant with children of its own, and a call of a seam or a public mock declare. A constant built in one expression
	/// declares none.
	nonisolated private func fillDeclaresFunction(fillPlaceBindings: FillPlaceBindings) -> Bool {
		guard let filled = propertiesToGenerate.first, let property = filled.property else { return false }
		return !property.propertyType.isConstant
			|| !filled.propertiesToGenerate.isEmpty
			|| filled.seamCall != nil
			|| filled.publicMockCall != nil
			// The builder function of a type that binds a place of an internal mock's fill (`FillPlace`).
			|| fillPlaceBindings.bindingsByGenerator[ObjectIdentifier(filled)] != nil
	}

	/// The places inside the fills this scope's call of another module's public mock declares, and inside the fills of the
	/// calls their trees make (`FillPlace`), in the order the fills and their trees are generated, with every label the types
	/// of those trees declare, which names a builder of the places apart from the trees' bindings.
	///
	/// A deliberate gap from the production twin, which takes one builder for a hole type: an internal mock of a type that
	/// generates no dependency tree takes a flat parameter for the same type its own tree instantiates outside every fill
	/// (`MockRootParameters.flatUncoveredParameters`), since flat parameters are its API and its own tree passes one value
	/// per name, and a builder only for the places inside fills, where its twin's fill calls the builder its seam takes. The
	/// other site of the gap is the mock root's `seamMockBuilders`.
	/// - Parameter insideSendableFunction: Whether the call is made inside a `@Sendable` function.
	nonisolated func fillPlaces(insideSendableFunction: Bool) -> (places: [FillPlace], declaredLabels: Set<String>) {
		var places = [FillPlace]()
		var declaredLabels = Set<String>()
		// A stack of its own, since a tree can be as deep as the module has types. Each scope's children are pushed in
		// reverse, so they are visited in the order they are generated.
		var generatorsToVisit = [(generator: ScopeGenerator, isInsideSendableFunction: Bool)]()
		func pushFills(of call: ScopeGenerator, insideSendableFunction: Bool) {
			for fill in call.propertiesToGenerate.reversed() where fill.fillHole != nil && fill.fillEmitsCode {
				let fillIsInsideSendableFunction = insideSendableFunction || call.buildsInSendableFunction(ofFill: fill)
				for child in fill.propertiesToGenerate.reversed() {
					generatorsToVisit.append((child, fillIsInsideSendableFunction))
				}
			}
		}
		pushFills(of: self, insideSendableFunction: insideSendableFunction)
		while let (generator, enclosingIsInsideSendableFunction) = generatorsToVisit.popLast() {
			// A scope that closes a cycle builds nothing; an alias builds nothing either.
			guard case let .property(instantiable, property, _, _, false, _) = generator.scopeData else { continue }
			declaredLabels.insert(property.label)
			let isInsideSendableFunction = enclosingIsInsideSendableFunction || generator.buildsInSendableFunction
			if generator.publicMockCall != nil {
				pushFills(of: generator, insideSendableFunction: isInsideSendableFunction)
			} else {
				let builtLabels = Set(generator.propertiesToGenerate.compactMap(\.property?.label))
				for dependency in instantiable.dependencies {
					declaredLabels.insert(dependency.property.label)
					if case .instantiated = dependency.source, !builtLabels.contains(dependency.property.label), DependencyTreeGenerator.canBeHole(dependency) {
						places.append(FillPlace(generator: ObjectIdentifier(generator), dependency: dependency, isInsideSendableFunction: isInsideSendableFunction, order: places.count))
					}
				}
				for child in generator.propertiesToGenerate.reversed() {
					generatorsToVisit.append((child, isInsideSendableFunction))
				}
			}
		}
		return (places, declaredLabels)
	}

	/// `code` with each line indented once more.
	private static func indented(_ code: String) -> String {
		code.split(separator: "\n", omittingEmptySubsequences: false).map { standardIndent + $0 }.joined(separator: "\n")
	}

	/// The arguments a builder function of a type whose `@Forwarded` properties are `forwardedProperties`, in their order,
	/// is passed from `forwardedValue`: the value itself for one property, and its elements by label for several.
	private static func forwardedArguments(of forwardedProperties: [Property], spreading forwardedValue: String) -> [String] {
		let isOnly = forwardedProperties.count == 1
		return forwardedProperties.map {
			CallArgument(label: $0.label, source: .forwardedSpread(label: $0.label, isOnly: isOnly, spreadName: forwardedValue)).spelled
		}
	}

	/// The declaration of this scope's instantiator, which hands its wrapper the function named `functionName`, called
	/// with `forwardedArguments`: the function itself when it takes no arguments and erases nothing, and otherwise a
	/// closure that calls it. Empty for a scope that builds no instantiator, which no caller asks.
	nonisolated private func instantiatorDeclaration(handing functionName: String, forwardedArguments: String) -> String {
		guard case let .property(instantiable, property, _, _, _, _) = scopeData else { return "" }
		// A type constructed by annotation spells its generic arguments only in the declaration.
		let unwrappedTypeDescription = property
			.typeDescription
			.unwrapped
			.spelledForConstruction
		let propertyDeclaration = BindingDeclaration(
			property: property,
			rule: .instantiator(isExtension: instantiable.declarationType.isExtension, constructionSpellsPropertyType: property.typeDescription.asSource == unwrappedTypeDescription),
		)
		return "\(propertyDeclaration.spelled) = \(instantiatorExpression(handing: functionName, forwardedArguments: forwardedArguments))"
	}

	/// The wrapper `instantiatorDeclaration(handing:forwardedArguments:)` declares.
	nonisolated private func instantiatorExpression(handing functionName: String, forwardedArguments: String) -> String {
		guard case let .property(_, property, _, erasedToConcreteExistential, _, _) = scopeData else { return "" }
		let unwrappedTypeDescription = property
			.typeDescription
			.unwrapped
			.spelledForConstruction
		return if forwardedArguments.isEmpty, !erasedToConcreteExistential {
			"\(unwrappedTypeDescription)(\(functionName))"
		} else if erasedToConcreteExistential {
			"""
			\(unwrappedTypeDescription) {
			\(Self.standardIndent)\(Expression.erasure(.call(function: functionName, arguments: forwardedArguments), as: property.typeDescription.unwrapped.asInstantiatedType).spelled)
			}
			"""
		} else {
			"""
			\(unwrappedTypeDescription) {
			\(Self.standardIndent)\(functionName)(\(forwardedArguments))
			}
			"""
		}
	}

	/// The declaration with which a member of a loop of builders rebinds this scope's instantiator, a member of the same
	/// loop, whose builder function its scope's body names `functionName` (see `ReceivedBuilderLoops`): the declaration the
	/// scope's body makes of it, which wraps the function again.
	nonisolated private func loopRebindingDeclaration(functionName: String) -> String {
		guard case let .property(_, _, forwardedProperties, _, _, _) = scopeData else { return "" }
		return instantiatorDeclaration(
			handing: functionName,
			forwardedArguments: Self.forwardedArguments(of: forwardedProperties.sorted(), spreading: "$0").joined(separator: ", "),
		)
	}

	/// The declaration with which a member of a loop of builders rebinds this scope, a rename its scope declares of a member
	/// of the same loop, whose rebinding is `fulfillingDeclaration`: the rename bound to a wrapper made again of the member's
	/// function. `nil` for any other scope.
	nonisolated private func loopRebindingDeclaration(ofRenameOf fulfillingDeclaration: (property: Property, generator: ScopeGenerator, functionName: String)) -> String? {
		guard case let .alias(property, _, _, _, _) = scopeData,
		      case let .property(_, _, forwardedProperties, _, _, _) = fulfillingDeclaration.generator.scopeData
		else { return nil }
		return Self.aliasDeclaration(
			of: property,
			fulfilledBy: fulfillingDeclaration.generator.instantiatorExpression(
				handing: fulfillingDeclaration.functionName,
				forwardedArguments: Self.forwardedArguments(of: forwardedProperties.sorted(), spreading: "$0").joined(separator: ", "),
			),
			ofType: fulfillingDeclaration.property.typeDescription,
			erasedToConcreteExistential: false,
			fulfillingValueMayBeOptional: false,
		)
	}

	private static func functionName(toBuild property: Property) -> String {
		functionName(toBuildPropertyNamed: property.label)
	}

	/// The name of the builder function for a property bound as `name`, which in a mock is the
	/// property's sibling-disambiguated label.
	static func functionName(toBuildPropertyNamed name: String) -> String {
		"\(ReservedName.builderFunctionNamePrefix)\(name)".spelledAsJoinedIdentifier
	}

	/// A declaration a builder function builds: its property, and the concrete type the scope declaring it builds. A
	/// cycle repeats a declaration only when both are the same (see `closedOnDeclaration`), so two declarations of one
	/// property that `fulfilledByType:` resolves to different types are two functions, and the nearer of the two can
	/// hide the farther's name from a cycle-closing scope beneath both (see `builderFunctionNames`).
	struct BuiltDeclaration: Hashable, Sendable {
		let property: Property
		let concreteType: TypeDescription
	}

	/// The names generated code refers to builder functions by, where they differ from `functionName(toBuild:)`.
	private struct BuilderFunctionNames: Hashable {
		/// The name of the scope's own builder function, or `nil` when it has the name it would have
		/// without renaming: `functionName(toBuild:)`, or in a mock its sibling-disambiguated name.
		var functionName: String?
		/// The names of the builder functions of enclosing scopes that a cycle-closing scope in the
		/// scope's subtree refers to, keyed by the declaration each builds, for those not named `functionName(toBuild:)`.
		var enclosingFunctionNames = [BuiltDeclaration: String]()
		/// For a fill, whether its function is `@Sendable` (see `buildsInSendableFunction(ofFill:)`).
		var fillIsSendable = false
		/// For a fill an override closure of its call is handed a function over (`publicMockOverrideBuilders`), whether its
		/// function takes each field of its case's payload it reads by itself, never the payload, which no other module can make.
		var fillTakesPayloadFields = false
		/// For a member of a loop of builders, the declarations with which the members of its loop are wrapped again, by
		/// their property: its builder function rebinds those its tree receives, and its `__safeDI_<label>_received`
		/// function those it passes as parameters a lazy cycle needs (see `ReceivedBuilderLoops`).
		var loopMemberDeclarations = [Property: String]()
		/// For a member of a loop of builders whose function takes parameters a lazy cycle needs, the name of the function
		/// of no such parameters its wrappers hand, which passes them; `nil` for every other scope.
		var receivedFunctionName: String?
		/// For a member of a loop of builders, the lines that bind the payloads of every member of its loop, which the first
		/// member emits before its declarations and every other member leaves out: a member's function can call any other
		/// member's, which reads that member's payload, so each is bound before the loop's first function. `nil` for every
		/// other scope, which binds its own payloads before its builder function.
		var loopValuesBindingLines: String?
		/// For a member of a loop its parent boxes (`boxedLoops`), the name of the box, from which its builder function
		/// first unboxes its own payloads and levels under their names; `nil` for every other scope.
		var loopLevelsName: String?
	}

	/// A child scope that one generated body holds, as builder function naming sees it.
	private struct BuilderFunctionCandidate {
		/// The property the child scope builds.
		let property: Property
		/// The declaration the child scope builds (see `ScopeGenerator.declaration`).
		let declaration: BuiltDeclaration
		/// The name of the child's builder function, unless it must be renamed, or `nil` when it is
		/// `functionName(toBuild:)`.
		let name: String?
		/// Whether the child may declare a builder function in the body: it is a property's scope
		/// that is not a cycle-closing scope. Renaming a child that declares none, such as a
		/// constant with nothing to build first, changes nothing it generates.
		let declaresFunction: Bool
		/// The child's `cycleClosedOnDeclarations`.
		let cycleClosedOnDeclarations: Set<BuiltDeclaration>
		/// The child's `isReferencedByCycleClosingScope`.
		let isReferencedByCycleClosingScope: Bool
		/// The names of the fills of enclosing calls that calls in the child's subtree refer to.
		let referencedFillNames: Set<String>
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
	/// all keep their names. A fill is named apart from the fills and builder parameters enclosing it when
	/// it is constructed (see `ScopeGeneratorUnderConstruction`), so a property's builder function is the
	/// only thing this renames.
	///
	/// - Parameter enclosingFunctionNames: The `BuilderFunctionNames.enclosingFunctionNames` of the
	///   scope whose body holds `children`.
	private static func builderFunctionNames(
		for children: [BuilderFunctionCandidate],
		enclosingFunctionNames: [BuiltDeclaration: String],
	) -> [BuilderFunctionNames] {
		let referencedFunctionNames = functionNamesReferenced(beneath: children, enclosingFunctionNames: enclosingFunctionNames)
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
		// safedi-source-rule: allow uniqueKeysWithValues — the keys are distinct indices of `children`.
		let renamedNameByIndex = Dictionary(uniqueKeysWithValues: zip(renamedIndices, renamedNames))
		return children.indices.map { index in
			let child = children[index]
			let renamedName = renamedNameByIndex[index]
			// A cycle-closing scope beneath the child refers to the functions enclosing it, and
			// to the child's own function when it is the one the cycle closes on.
			var childEnclosingFunctionNames = child.cycleClosedOnDeclarations.isEmpty ? [:] : enclosingFunctionNames
			let childFunctionName = renamedName ?? childNames[index]
			if child.isReferencedByCycleClosingScope, childFunctionName != functionName(toBuild: child.property) {
				childEnclosingFunctionNames[child.declaration] = childFunctionName
			}
			return BuilderFunctionNames(
				functionName: renamedName,
				enclosingFunctionNames: childEnclosingFunctionNames,
			)
		}
	}

	/// The names of the functions enclosing the body that holds `children` that a scope in a child's subtree refers to by
	/// name, so that no function the body declares may share them: the function each cycle-closing scope closes on, and
	/// each fill of an enclosing seam call that a call inside it passes on.
	/// - Parameter enclosingFunctionNames: The `BuilderFunctionNames.enclosingFunctionNames` of the scope whose body
	///   holds `children`.
	private static func functionNamesReferenced(
		beneath children: [BuilderFunctionCandidate],
		enclosingFunctionNames: [BuiltDeclaration: String],
	) -> Set<String> {
		var referencedDeclarations = Set<BuiltDeclaration>()
		for child in children where !child.cycleClosedOnDeclarations.isEmpty {
			referencedDeclarations.formUnion(child.cycleClosedOnDeclarations)
		}
		// A call inside a fill of its seam's call refers to the fill by name, as a cycle-closing scope refers to the
		// function it closes on, so no builder function between the two may share that name either.
		return Set(referencedDeclarations.map {
			enclosingFunctionNames[$0, default: functionName(toBuild: $0.property)]
		}).union(children.flatMap(\.referencedFillNames))
	}

	/// The names a `__safeDI_<label>_received` function this scope's body declares must not take (see
	/// `ReceivedBuilderLoops`), since Swift resolves a name to the innermost declaration of it in scope and a local function
	/// is in scope throughout the body that declares it: the builder functions the body declares, the enclosing functions
	/// and fills a scope beneath refers to by name and the names a seam's initializer binds, which the function would hide,
	/// and the functions each member of a loop
	/// declares in its own body, where its rebindings read the function and would resolve to them. A member's builder
	/// function is named after its label (renamed only beside a cycle-closing scope beneath that refers to an enclosing
	/// function of its name), and so is the `__safeDI_<label>_received` function of a loop in the member's body, so both
	/// are counted for each of the member's children that declares a builder function. A seam call's fills and dispatchers
	/// are declared in the body of the call's own builder function, which holds nothing else, so no loop is beside them.
	/// - Parameters:
	///   - childBuilderFunctionNames: The names each of `orderedChildren` was given, where the body renames any.
	///   - loopMembers: The children on a loop of builders.
	///   - enclosingFunctionNames: This scope's `BuilderFunctionNames.enclosingFunctionNames`.
	nonisolated private func namesReceivedFunctionsAvoid(
		orderedChildren: [OrderedChild],
		childBuilderFunctionNames: [BuilderFunctionNames?]?,
		loopMembers: [ScopeGenerator],
		enclosingFunctionNames: [BuiltDeclaration: String],
	) -> Set<String> {
		var names = Self.functionNamesReferenced(
			beneath: orderedChildren.compactMap(\.generator.builderFunctionCandidate),
			enclosingFunctionNames: enclosingFunctionNames,
		).union(namesBoundBySeam)
		for (index, child) in orderedChildren.enumerated() {
			if child.generator.declaresBuilderFunction, let property = child.generator.property {
				names.insert((childBuilderFunctionNames?[index] ?? nil)?.functionName ?? Self.functionName(toBuild: property))
			}
		}
		for member in loopMembers {
			for child in member.propertiesToGenerate where child.declaresBuilderFunction {
				if let property = child.property {
					let functionName = Self.functionName(toBuild: property)
					names.insert(functionName)
					names.insert(ReservedName.receivedBuilderFunctionName(of: functionName))
				}
			}
		}
		return names
	}

	/// This scope as a child that a generated body holds, for `builderFunctionNames`, or `nil` for a
	/// root, which no body holds.
	nonisolated private var builderFunctionCandidate: BuilderFunctionCandidate? {
		declaration.map { declaration in
			BuilderFunctionCandidate(
				property: declaration.property,
				declaration: declaration,
				name: nil,
				declaresFunction: declaresBuilderFunction,
				cycleClosedOnDeclarations: cycleClosedOnDeclarations,
				isReferencedByCycleClosingScope: isReferencedByCycleClosingScope,
				referencedFillNames: Set(referencedFillNamesByKey.values),
			)
		}
	}

	static let standardIndent = "    "

	/// The empty enum a seam's or a public mock's module generates beside the code it generates for `typeName`, named for
	/// the signature that code was generated from, which every call of that code names on the line before it
	/// (`SeamCall.guardLine(for:)`, `PublicMockCall.guardLine(for:)`), so that a call generated from another signature
	/// fails to compile there.
	static func guardEnumDeclaration(extending typeName: String, named guardTypeName: String) -> String {
		"""
		extension \(typeName) {
		\(standardIndent)public enum \(guardTypeName) {}
		}
		"""
	}

	// MARK: Code Generation

	/// Generates code for this scope. Dependency-tree mode emits the full subtree
	/// recursively. Mock mode only reaches this function for `.root` scopes, which
	/// delegate to `generateMockRootCode`; non-root mock code is produced via
	/// `collectMockParameterTree` + `generateMockBodyBindings` instead.
	///
	/// Never inlined: its frame holds a slot for each of its branches, and inlined into `generateCode`, which every scope
	/// awaits each child's code in, it made every such frame as large as its own.
	@inline(never)
	private func generatePropertyCode(
		codeGeneration: CodeGeneration,
		unavailableProperties: Set<Property>,
		propertiesGeneratedLater: Set<Property>,
		builderFunctionNames: BuilderFunctionNames,
		fillPlaceBindings: FillPlaceBindings,
	) async throws -> GeneratedCode {
		switch scopeData {
		case let .root(instantiable, seamRoot):
			switch codeGeneration {
			case .dependencyTree:
				if let seamRoot {
					return try await .text(generateSeamRootCode(
						instantiable: instantiable,
						seamRoot: seamRoot,
						unavailableProperties: unavailableProperties,
						propertiesGeneratedLater: propertiesGeneratedLater,
						builderFunctionNames: builderFunctionNames,
						fillPlaceBindings: fillPlaceBindings,
					))
				}
				guard let rootInitializer = try Self.rootInitializer(of: instantiable) else { return .empty }
				let childCode = try await generateProperties(
					propertiesGeneratedLater: propertiesGeneratedLater,
					enclosingFunctionNames: builderFunctionNames.enclosingFunctionNames,
					leadingMemberWhitespace: "        ",
					fillPlaceBindings: fillPlaceBindings,
				)
				return Self.rootCode(of: rootInitializer, writing: consume childCode)
			case let .mock(context):
				return try await .text(generateMockRootCode(
					instantiable: instantiable,
					context: context,
				))
			}
		case let .property(
			instantiable,
			property,
			forwardedProperties,
			erasedToConcreteExistential,
			isPropertyCycle,
			seamCall,
		):
			// Only the children's code is awaited here: what the scope writes around it is decided and spelled by the
			// synchronous functions below (`.claude/rules/emission-decisions.md`, "A spelling holds no subtree text longer").
			let argumentList = try constructionArgumentList(of: instantiable, unavailableProperties: unavailableProperties)
			if isPropertyCycle, let closingCode = cycleClosingCode(
				of: property,
				erasedToConcreteExistential: erasedToConcreteExistential,
				unavailableProperties: unavailableProperties,
				builderFunctionNames: builderFunctionNames,
			) {
				return .text(closingCode)
			}
			let childCode = try await generateProperties(
				codeGeneration: codeGeneration,
				propertiesGeneratedLater: bodyPropertiesGeneratedLater(propertiesGeneratedLater),
				enclosingFunctionNames: builderFunctionNames.enclosingFunctionNames,
				leadingMemberWhitespace: Self.standardIndent,
				fillPlaceBindings: fillPlaceBindings,
			)
			return propertyCode(
				around: childCode,
				instantiable: instantiable,
				property: property,
				forwardedProperties: forwardedProperties,
				erasedToConcreteExistential: erasedToConcreteExistential,
				isPropertyCycle: isPropertyCycle,
				seamCall: seamCall,
				argumentList: argumentList,
				unavailableProperties: unavailableProperties,
				builderFunctionNames: builderFunctionNames,
				fillPlaceBindings: fillPlaceBindings,
			)
		case let .hole(property, _, site):
			// A tree built only to compute the seam's signature has no site, and generates nothing.
			guard let site else { return .empty }
			return .text(Self.buildSiteCode(of: property, at: site, functionName: builderFunctionNames.functionName, readingInstancesOf: callSiteLazilyInstantiatedInstanceProperties, isNonisolated: sendableFunctionsAreNonisolated))
		case let .fill(hole, functionName):
			// A fill is hosted as its text until fills are planned (`.claude/rules/emission-decisions.md`).
			return try await .text(generateFillCode(
				of: hole,
				functionName: functionName,
				isSendable: builderFunctionNames.fillIsSendable,
				takesPayloadFields: builderFunctionNames.fillTakesPayloadFields,
				codeGeneration: codeGeneration,
				propertiesGeneratedLater: propertiesGeneratedLater,
				enclosingFunctionNames: builderFunctionNames.enclosingFunctionNames,
				fillPlaceBindings: fillPlaceBindings,
			))
		case let .alias(property, fulfillingProperty, erasedToConcreteExistential, onlyIfAvailable, declarationReference):
			return .text(aliasCode(
				of: property,
				fulfilledBy: fulfillingProperty,
				erasedToConcreteExistential: erasedToConcreteExistential,
				onlyIfAvailable: onlyIfAvailable,
				declarationReference: declarationReference,
				unavailableProperties: unavailableProperties,
			))
		}
	}

	/// The initializer generated for `instantiable`, a root of the dependency tree, or `nil` for a root without
	/// dependencies, for which nothing is generated (`RootInitializer.init(of:argumentList:)`).
	@inline(never)
	private static func rootInitializer(of instantiable: Instantiable) throws -> RootInitializer? {
		try RootInitializer(of: instantiable, argumentList: instantiable.generateArgumentList())
	}

	/// The extension `rootInitializer` declares, writing `childCode`, the code of the root's children.
	@inline(never)
	private static func rootCode(of rootInitializer: RootInitializer, writing childCode: consuming [GeneratedCode]) -> GeneratedCode {
		rootInitializer.spelled(writing: BuilderFunctionGraph(body: childCode.map(Statement.verbatim)))
	}

	/// The declaration of the alias `property`, which `fulfillingProperty` fulfills.
	@inline(never)
	private func aliasCode(
		of property: Property,
		fulfilledBy fulfillingProperty: Property,
		erasedToConcreteExistential: Bool,
		onlyIfAvailable: Bool,
		declarationReference: AliasDeclarationReferences.Reference?,
		unavailableProperties: Set<Property>,
	) -> String {
		if Self.aliasIsBoundToNil(onlyIfAvailable: onlyIfAvailable, fulfillingProperty: fulfillingProperty, unavailableProperties: unavailableProperties) {
			// An `onlyIfAvailable` alias whose fulfilling property is unavailable is still declared, so that its declaring
			// type and everything beneath it read it, `nil` included, rather than a declaration of its label further up.
			Self.referencingDeclaration(of: "let \(property.asSource) = nil", by: declarationReference)
		} else {
			// The alias is bound from the declared property it reads, which may be `nil` where it is an optional
			// property – a seam's optional parameter, a parameter made optional, or the optional form of the fulfilling
			// property – and is otherwise a non-optional value. A wrapper's instance is read from a non-optional wrapper.
			Self.referencingDeclaration(
				of: Self.aliasDeclaration(
					of: property,
					fulfilledBy: fulfillingExpression ?? (fulfillingPropertyIsLazilyInstantiatedInstance
						? "\(fulfillingProperty.label).\(Dependency.lazilyInstantiatedInstancePropertyName)"
						: fulfillingProperty.label),
					ofType: fulfillingProperty.typeDescription,
					erasedToConcreteExistential: erasedToConcreteExistential,
					fulfillingValueMayBeOptional: fulfillingBindingIsOptional,
				),
				by: declarationReference,
			)
		}
	}

	// A property's scope is written by the synchronous functions below, as a root's and an alias's are by those above,
	// and `generatePropertyCode` only awaits its children's code between them. A task holds the async frame of every call
	// it is suspended in, and a large subtree starts each small subtree beneath it on a task of its own, so a wide tree
	// holds one such frame for each of its scopes at once: every value decided or spelled inside the async function made
	// each of them larger. Each function is kept out of the async function (`@inline(never)`), so that what it decides
	// lives on a thread's stack while it runs.

	/// What the construction of `instantiable` in this scope's builder function passes the function it calls.
	@inline(never)
	private func constructionArgumentList(of instantiable: Instantiable, unavailableProperties: Set<Property>) throws -> String {
		// A type built with its hand-written mock, as one built with its initializer, is constructed inside its builder
		// function, whose own parameters hide the declarations of their labels where it is called.
		if publicMockCall != nil, let mockInitializer = instantiable.mockInitializer {
			// A call of another module's public mock in a fill a mock declares, which passes each parameter of the tier
			// in signature order, a builder it fills among them, and no `safeDIOverrides`: no override reaches a fill. A
			// by-value parameter whose label the tree holds as a lazily instantiated property is passed its instance, as
			// a call outside a fill is (`dependencyArgument`).
			mockInitializer.arguments.map { argument in
				let dependency = instantiable.dependencies.first { $0.property.label == argument.innerLabel }
				let source: ArgumentSource = if let builderValue = publicMockBuilderStructValuesByLabel[argument.innerLabel] {
					.builderArgument(builderValue)
				} else if let holeValue = holeArgumentValuesByLabel[argument.innerLabel] {
					.holeArgument(holeValue)
				} else if let dependency, unavailableProperties.contains(dependency.property) {
					.nil
				} else if let dependency, dependency.source.isReceived, lazilyInstantiatedInstanceProperties.contains(dependency.property.asUnwrappedProperty) {
					.lazyInstance(label: argument.innerLabel, throughOptional: false)
				} else {
					// A parameter no dependency takes reads the nearest declaration of its label, as a dependency does.
					.binding(label: argument.innerLabel)
				}
				return CallArgument(label: argument.label, source: source).spelled
			}.joined(separator: ", ")
		} else if constructsWithHandWrittenMock, let mockInitializer = instantiable.mockInitializer {
			// A type a fill builds with its hand-written mock is passed what the mock takes of its dependencies, as an
			// initializer is; each other parameter of the mock keeps its default. One without a default, whose dependency
			// only an inactive clause declares, reaches here only in a build that compiles no generated mock, which never
			// compiles the call, as it never compiles the same call outside a fill.
			mockInitializer.createHandWrittenMockArgumentList(
				given: instantiable.dependencies,
				unavailableProperties: bodyUnavailableProperties(unavailableProperties),
				lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties,
			)
		} else {
			// A public mock takes a value its tree receives lazily as the wrapper, so a call of one passes the caller's own
			// (`ScopeGenerator.publicMockWrapperParameters`). A deliberate gap, the other site of which is that function: where
			// the called mock still takes the value by value, a call passes a `LazilyInstantiated` property's instance
			// (`<label>.instance`), which is created at the call, even when nothing in the called mock's tree reads it.
			try instantiable.generateArgumentList(
				unavailableProperties: bodyUnavailableProperties(unavailableProperties),
				lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties,
			)
		}
	}

	/// The code of this scope where it closes a cycle on `property`, lazily instantiated or constant: it declares no
	/// function, and refers to the function of the declaration it repeats with that function's cycle parameters. `nil`
	/// for an instantiator, which generates its children as every other scope does.
	@inline(never)
	private func cycleClosingCode(
		of property: Property,
		erasedToConcreteExistential: Bool,
		unavailableProperties: Set<Property>,
		builderFunctionNames: BuilderFunctionNames,
	) -> String? {
		switch property.propertyType {
		case .instantiator,
		     .erasedInstantiator,
		     .sendableInstantiator,
		     .sendableErasedInstantiator:
			return nil
		case .lazilyInstantiated,
		     .sendableLazilyInstantiated:
			// It hands its wrapper the function of the declaration it repeats, as an instantiator that closes a cycle does.
			let lazilyInstantiatedInstantiation = Self.lazilyInstantiatedInstantiation(
				of: property,
				callingFunctionNamed: closedOnFunctionName(builtFor: property, enclosingFunctionNames: builderFunctionNames.enclosingFunctionNames),
				cycleArguments: cycleParameterArguments(unavailableProperties: unavailableProperties).joined(separator: ", "),
				erasedToConcreteExistential: erasedToConcreteExistential,
			)
			return "\(builderFunctionNames.loopValuesBindingLines ?? valuesBindingLines)\(BindingDeclaration(property: property, rule: .lazilyInstantiated).spelled) = \(lazilyInstantiatedInstantiation)"
		case .constant:
			// It is typed as a constant with content is. A closer builds nothing, so it holds no seam's site and
			// `valuesBindingLines` is empty, as it is for every closer.
			let valuesBindingLines = builderFunctionNames.loopValuesBindingLines ?? valuesBindingLines
			let callArguments = cycleParameterArguments(unavailableProperties: unavailableProperties).joined(separator: ", ")
			let call = Expression.call(function: closedOnFunctionName(builtFor: property, enclosingFunctionNames: builderFunctionNames.enclosingFunctionNames), arguments: callArguments)
			return if erasedToConcreteExistential {
				"\(valuesBindingLines)let \(property.label) = \(Expression.erasure(call, as: property.typeDescription).spelled)\n"
			} else {
				"\(valuesBindingLines)let \(property.asSource) = \(call.spelled)\n"
			}
		}
	}

	/// The wrapper a lazily instantiated `property` is declared as, which calls the builder function named `functionName`
	/// with `cycleArguments` the first time its instance is requested. The wrapper is always spelled with its generic
	/// argument, so the declaration needs no type annotation: an optional property receives the wrapper through optional
	/// promotion.
	private static func lazilyInstantiatedInstantiation(
		of property: Property,
		callingFunctionNamed functionName: String,
		cycleArguments: String,
		erasedToConcreteExistential: Bool,
	) -> String {
		let unwrappedTypeDescription = property
			.typeDescription
			.unwrapped
			.asSource
		return if erasedToConcreteExistential {
			"""
			\(unwrappedTypeDescription) {
			\(Self.standardIndent)\(Expression.erasure(.call(function: functionName, arguments: cycleArguments), as: property.typeDescription.asInstantiatedType).spelled)
			}
			"""
		} else if cycleArguments.isEmpty {
			"\(unwrappedTypeDescription)(\(functionName))"
		} else {
			"""
			\(unwrappedTypeDescription) {
			\(Self.standardIndent)\(functionName)(\(cycleArguments))
			}
			"""
		}
	}

	/// The code of this scope, which builds `property` from `instantiable`, written around `childCode`, its children's
	/// code: the builder function, where the scope declares one, and the declaration of the property. A scope that closes
	/// a lazily instantiated or constant cycle is written by `cycleClosingCode(of:erasedToConcreteExistential:unavailableProperties:builderFunctionNames:)`.
	/// - Parameter argumentList: What the construction passes the function it calls
	///   (`constructionArgumentList(of:unavailableProperties:)`).
	@inline(never)
	private func propertyCode(
		around childCode: [GeneratedCode],
		instantiable: Instantiable,
		property: Property,
		forwardedProperties: Set<Property>,
		erasedToConcreteExistential: Bool,
		isPropertyCycle: Bool,
		seamCall: SeamCall?,
		argumentList: String,
		unavailableProperties: Set<Property>,
		builderFunctionNames: BuilderFunctionNames,
		fillPlaceBindings: FillPlaceBindings,
	) -> GeneratedCode {
		let concreteTypeName = instantiable.concreteInstantiable.asSource
		let constructionTarget: ConstructionTarget = if let publicMockCall {
			.mock(instantiable.concreteInstantiable, name: publicMockCall.functionName)
		} else if constructsWithHandWrittenMock {
			.mock(instantiable.concreteInstantiable, name: instantiable.customMockName ?? InstantiableVisitor.mockMethodName)
		} else if instantiable.declarationType.isExtension {
			.instantiate(instantiable.concreteInstantiable)
		} else {
			.initializer(instantiable.concreteInstantiable)
		}
		// A seam call passes a builder for each of the seam's holes after the tier's parameters; a call of a public
		// mock passes them among its arguments.
		let holeArgumentList = publicMockCall == nil
			? builderCallArguments.map { "\($0.label): \($0.value)" }
			: []
		let constructionArguments = holeArgumentList.isEmpty ? argumentList : ([argumentList].filter { !$0.isEmpty } + holeArgumentList).joined(separator: ", ")
		let construction = Expression.construction(constructionTarget, arguments: constructionArguments)
		// The payloads of the cases on the routes to the places beneath this scope, bound before its builder function, where
		// the scope's parent binds its labels: each field read as the parent's receivers read it.
		let valuesBindingLines = builderFunctionNames.loopValuesBindingLines ?? valuesBindingLines
		// What ends the line that constructs the type, after the construction. A seam built inline here is built with the
		// caller's isolation; across modules, its generated initializer builds its tree with the type's isolation, or the
		// one `generatedInitializerAttributes` spells. A deliberate gap, which
		// `generateSeamRootCode`'s comment on the generated initializers' isolation states too.
		let constructionLineEnd = builtInlineSeamComment.map { " \($0)" } ?? ""
		// A call to a seam's generated initializer refers to the enum the seam's module generated for the
		// signature the call was generated from, on the line before the call, so a call generated from another
		// signature fails to compile here rather than pass `nil` where the initializer expects a value. The
		// statement is emitted as the body's only generated property, so the call is made in a builder function.
		let seamGuardLines: [GeneratedCode] = if let seamCall {
			[.text("\(Self.standardIndent)\(seamCall.guardLine(for: instantiable.concreteInstantiable))")]
		} else {
			[]
		}
		// A type inside a fill an internal mock declares binds each place of it nothing builds from the builder `mock()`
		// takes for the place (`FillPlace`), once per build, before its children, which receive the place's value.
		let fillPlaceBindingLines = fillPlaceBindings.bindingsByGenerator[ObjectIdentifier(self), default: []].map { GeneratedCode.text("\(Self.standardIndent)\($0.binding)") }
		let memberCallLines = self.memberCallLines.map(GeneratedCode.text)

		let propertyType = property.propertyType
		switch propertyType {
		case .instantiator,
		     .erasedInstantiator,
		     .sendableInstantiator,
		     .sendableErasedInstantiator:
			let forwardedProperties = forwardedProperties.sorted()
			// The wrapper's closure spreads its argument.
			let forwardedValue = "$0"
			let forwardedArguments = (
				Self.forwardedArguments(of: forwardedProperties, spreading: forwardedValue)
					+ cycleParameterArguments(unavailableProperties: unavailableProperties),
			).joined(separator: ", ")
			// A member of a loop of builders first wraps again the functions of the members its tree receives inside the
			// loop, each as the member's own declaration wraps it, so each receiver beneath reads a wrapper this call made.
			// A cycle-closing scope declares no function: it refers to the enclosing one it closes on.
			let functionName = if isPropertyCycle {
				closedOnFunctionName(builtFor: property, enclosingFunctionNames: builderFunctionNames.enclosingFunctionNames)
			} else {
				builderFunctionNames.functionName ?? Self.functionName(toBuild: property)
			}
			let rebindingLines = reboundProperties.compactMap { reboundProperty in
				if reboundProperty == property, declaresCycleParameters {
					// The function's own property is wrapped again with the function's own parameters: where a cycle-closing
					// scope builds the tree again, they are that scope's, which is then the nearest declaration of each.
					Self.indented(instantiatorDeclaration(
						handing: functionName,
						forwardedArguments: (
							Self.forwardedArguments(of: forwardedProperties, spreading: "$0")
								+ cycleParameters.map { CallArgument(label: $0.property.label, source: .binding(label: $0.property.label)).spelled },
						).joined(separator: ", "),
					))
				} else {
					builderFunctionNames.loopMemberDeclarations[reboundProperty].map(Self.indented)
				}
			}
			// A member of a boxed loop first unboxes its own payloads, which the scope bound in the loop's box.
			let unboxingLines = builderFunctionNames.loopLevelsName.map(loopLevelsUnboxingLines(from:)) ?? []
			// A fill that returns the builder the wrapper keeps is handed, for each struct of its own level, the function the inner
			// seam's member returns, which takes the forwarded value: the builder function calls it with what it was forwarded,
			// `()` where it forwards nothing, one value as itself, several as the labeled tuple the wrapper forwards.
			var forwardedInnerScopeLines = [String]()
			if isBuiltByFill, fillReturnsWrapperBuilder, readsFillInnerScopes {
				let forwardedValue = switch forwardedProperties.count {
				case 0: "()"
				case 1: forwardedProperties[0].label
				default: "(\(forwardedProperties.map { "\($0.label.spelledAsArgumentLabel): \($0.label)" }.joined(separator: ", ")))"
				}
				forwardedInnerScopeLines = innerScopesCalledWithForwardedValue.map { "\(Self.standardIndent)let \($0) = \($0)(\(forwardedValue))" }
			}
			// Appended part by part: Linux's Swift 6.2 cannot type-check these parts joined with `+` in one expression ("the
			// compiler is unable to type-check this expression in reasonable time").
			var generatedProperties = unboxingLines.map(GeneratedCode.text)
			generatedProperties += forwardedInnerScopeLines.map(GeneratedCode.text)
			generatedProperties += memberCallLines
			generatedProperties += rebindingLines.map(GeneratedCode.text)
			generatedProperties += seamGuardLines
			generatedProperties += fillPlaceBindingLines
			generatedProperties += childCode
			// The function a lazy cycle closes on also takes the parameters its cycle-closing scopes pass.
			let functionParameters = forwardedProperties + (isPropertyCycle ? [] : cycleParameters.map(\.property))
			let functionDeclaration: GeneratedCode = if isPropertyCycle {
				.empty
			} else {
				Statement.function(BuilderNode(
					name: functionName,
					isSendable: buildsInSendableFunction,
					// A fill that returns a wrapper's builder spells its builder function `nonisolated` where it is `@Sendable`, as
					// the code that calls the fill is.
					isNonisolated: fillReturnsWrapperBuilder || sendableFunctionsAreNonisolated,
					parameters: functionParameters,
					typesDeclaredEscaping: typesDeclaredEscaping,
					returnType: instantiable.concreteInstantiable,
					body: BuilderBody(statements: generatedProperties),
					value: construction,
					lineEnd: constructionLineEnd,
				)).spelled
			}

			guard !isBuiltByFill else {
				// A fill returns the builder the wrapper keeps (`fillReturnsWrapperBuilder`): a closure that hands the builder function what the wrapper forwards, named, and
				// spread by label where it is several values, never destructured.
				// Named apart from the parameters a lazy cycle passes, which the call reads by their labels.
				var forwardedName = "forwarded"
				while cycleParameters.contains(where: { $0.property.label == forwardedName }) {
					forwardedName += "_"
				}
				var builderArguments = Self.forwardedArguments(of: forwardedProperties, spreading: forwardedName)
				builderArguments += cycleParameterArguments(unavailableProperties: unavailableProperties)
				let builtValue = Expression.call(function: functionName, arguments: builderArguments.joined(separator: ", "))
					.erased(to: property.typeDescription.unwrapped.asInstantiatedType, where: erasedToConcreteExistential)
					.spelled
				return .sequence([.text(valuesBindingLines), functionDeclaration, .text("return { \(forwardedProperties.isEmpty ? "_" : forwardedName) in \(builtValue) }")])
			}
			if let receivedFunctionName = builderFunctionNames.receivedFunctionName {
				// The function every wrapper of this member hands: it passes the parameters a lazy cycle needs what this
				// scope's body binds, and a member of the same loop as a wrapper it makes, which no wrapper the body
				// declares later can be.
				var memberLines = [String]()
				let cycleArguments = zip(cycleParameters, cycleParameterArguments(unavailableProperties: unavailableProperties)).map { parameter, argument in
					// A scope declares each label once, so at most one of the two forms is a member.
					let unwrappedProperty = parameter.property.asUnwrappedProperty
					let memberDeclaration = builderFunctionNames.loopMemberDeclarations[unwrappedProperty] ?? builderFunctionNames.loopMemberDeclarations[unwrappedProperty.asOptionalProperty]
					if let memberDeclaration {
						memberLines.append(Self.indented(memberDeclaration))
						return CallArgument(label: parameter.property.label, source: .binding(label: parameter.property.label)).spelled
					} else {
						return argument
					}
				}
				let receivedFunctionParameters = forwardedProperties.isEmpty
					? ""
					: forwardedProperties.initializerFunctionParameters(amongTypesDeclaredEscaping: typesDeclaredEscaping).map(\.description).joined()
				let callArguments = (forwardedProperties.map { CallArgument(label: $0.label, source: .binding(label: $0.label)).spelled } + cycleArguments).joined(separator: ", ")
				let receivedFunctionDecorator = buildsInSendableFunction || property.propertyType.isSendable ? sendableFunctionDecorator : ""
				let receivedFunctionDeclaration = """
				\(receivedFunctionDecorator)func \(receivedFunctionName)(\(receivedFunctionParameters)) -> \(concreteTypeName) {
				\((memberLines + ["\(Self.standardIndent)\(BuilderBody(statements: memberLines.map(GeneratedCode.text)).returnKeyword)\(functionName)(\(callArguments))"]).joined(separator: "\n"))
				}

				"""
				return .sequence([
					.text(valuesBindingLines),
					functionDeclaration,
					.text(receivedFunctionDeclaration + instantiatorDeclaration(
						handing: receivedFunctionName,
						forwardedArguments: Self.forwardedArguments(of: forwardedProperties, spreading: forwardedValue).joined(separator: ", "),
					)),
				])
			}
			return .sequence([.text(valuesBindingLines), functionDeclaration, .text(instantiatorDeclaration(handing: functionName, forwardedArguments: forwardedArguments))])
		case .lazilyInstantiated,
		     .sendableLazilyInstantiated:
			// The builder function is the one a constant with children declares. A constant calls it
			// immediately; a lazily instantiated property hands it to its wrapper, which calls it the
			// first time the instance is requested. Dependency cycle validation treats the property
			// as a constant, so it is never the deferred hop of a cycle.
			let cycleArguments = cycleParameterArguments(unavailableProperties: unavailableProperties).joined(separator: ", ")
			let functionName = builderFunctionNames.functionName ?? Self.functionName(toBuild: property)
			let generatedProperties = memberCallLines + seamGuardLines + fillPlaceBindingLines + childCode
			// The function a cycle closes on also takes the parameters its cycle-closing scopes pass.
			let function = BuilderNode(
				name: functionName,
				isSendable: buildsInSendableFunction,
				isNonisolated: sendableFunctionsAreNonisolated,
				parameters: cycleParameters.map(\.property),
				typesDeclaredEscaping: typesDeclaredEscaping,
				returnType: instantiable.concreteInstantiable,
				body: BuilderBody(statements: generatedProperties),
				value: construction,
				lineEnd: constructionLineEnd,
			)
			let lastLine = if isBuiltByFill {
				"return \(Expression.call(function: functionName, arguments: cycleArguments).erased(to: property.typeDescription.asInstantiatedType, where: erasedToConcreteExistential).spelled)"
			} else {
				"\(BindingDeclaration(property: property, rule: .lazilyInstantiated).spelled) = \(Self.lazilyInstantiatedInstantiation(of: property, callingFunctionNamed: functionName, cycleArguments: cycleArguments, erasedToConcreteExistential: erasedToConcreteExistential))"
			}

			return function.spelled(after: valuesBindingLines, followedBy: lastLine)
		case .constant:
			let callArguments = cycleParameterArguments(unavailableProperties: unavailableProperties).joined(separator: ", ")
			let generatedProperties = memberCallLines + seamGuardLines + fillPlaceBindingLines + childCode
			let body = BuilderBody(statements: generatedProperties)
			let hasGeneratedContent = body.hasStatements
			let propertyDeclaration = BindingDeclaration(
				property: property,
				rule: .constant(
					isErased: erasedToConcreteExistential,
					constructedTypeIsPropertyType: concreteTypeName == property.typeDescription.asSource,
					hasBuilderFunction: hasGeneratedContent,
					isExtension: instantiable.declarationType.isExtension,
				),
			)

			// Ideally we would be able to use an anonymous closure rather than a named function here.
			// Unfortunately, there's a bug in Swift Concurrency that prevents us from doing this: https://github.com/swiftlang/swift/issues/75003
			let functionName = builderFunctionNames.functionName ?? Self.functionName(toBuild: property)
			let functionDeclaration: GeneratedCode = if !hasGeneratedContent {
				.empty
			} else {
				// The function a cycle closes on also takes the parameters its cycle-closing scopes pass.
				Statement.function(BuilderNode(
					name: functionName,
					isSendable: buildsInSendableFunction,
					isNonisolated: sendableFunctionsAreNonisolated,
					parameters: cycleParameters.map(\.property),
					typesDeclaredEscaping: typesDeclaredEscaping,
					returnType: instantiable.concreteInstantiable,
					body: body,
					value: construction,
					lineEnd: constructionLineEnd,
				)).spelled
			}
			let binding = if !hasGeneratedContent {
				Statement.binding(propertyDeclaration, construction.erased(to: property.typeDescription, where: erasedToConcreteExistential), lineEnd: constructionLineEnd)
			} else {
				Statement.binding(propertyDeclaration, Expression.call(function: functionName, arguments: callArguments).erased(to: property.typeDescription, where: erasedToConcreteExistential), lineEnd: "")
			}

			// The payloads a seam's tree binds before building a scope that leads to a place.
			return .sequence([.text(valuesBindingLines), functionDeclaration, binding.spelled, .text("\n")])
		}
	}

	private static func structDeclaration(named name: String, fields: [SeamSignature.Hole.Field], indent: String, typesDeclaredEscaping: Set<TypeDescription>, isNonisolated: Bool = false) -> String {
		let declarationPrefix = isNonisolated ? "\(indent)nonisolated public struct" : "\(indent)public struct"
		guard !fields.isEmpty else { return "\(declarationPrefix) \(name) {}" }
		let memberIndent = "\(indent)\(standardIndent)"
		let fieldDeclarations = fields.map { field in
			if field.isDeferredParameter {
				"\(memberIndent)\(field.access.spelledOnGeneratedDeclaration) var \(field.property.label.spelledAsMemberDeclarationName): \(field.property.typeDescription.asSource) { \(field.memoName).\(Dependency.lazilyInstantiatedInstancePropertyName) }"
			} else {
				"\(memberIndent)\(field.access.spelledOnGeneratedDeclaration) let \(field.property.label.spelledAsMemberDeclarationName): \(field.property.typeDescription.asSource)"
			}
		}
		let memoFields = fields.filter(\.isDeferredParameter)
		guard !memoFields.isEmpty else {
			return (["\(declarationPrefix) \(name) {"] + fieldDeclarations + ["\(indent)}"]).joined(separator: "\n")
		}
		let memoDeclarations = memoFields.compactMap { field in
			// The memo is as visible as its field, so a fill in another module binds it and reads its instance where its tree
			// reads the value.
			field.memoType.map { "\(memberIndent)\(field.access.spelledOnGeneratedDeclaration) let \(field.memoName): \($0.asSource)" }
		}
		let initializerParameters = fields.map { field in
			"\(field.property.label.spelledAsArgumentLabel): \((field.memoType ?? field.property.typeDescription.asFunctionParameter(amongTypesDeclaredEscaping: typesDeclaredEscaping)).asSource)"
		}
		let initializerAssignments = fields.map { field in
			if field.isDeferredParameter {
				"\(memberIndent)\(standardIndent)\(field.memoName) = \(field.property.label)"
			} else {
				"\(memberIndent)\(standardIndent)self.\(field.property.label.spelledAsMemberReference) = \(field.property.label)"
			}
		}
		// Appended part by part, for Swift 6.2: it cannot type-check one `+` chain of these arrays in reasonable time.
		var lines = ["\(declarationPrefix) \(name) {"]
		lines += fieldDeclarations
		lines += memoDeclarations
		lines.append("")
		lines.append("\(memberIndent)init(\(initializerParameters.joined(separator: ", "))) {")
		lines += initializerAssignments
		lines.append("\(memberIndent)}")
		lines.append("\(indent)}")
		return lines.joined(separator: "\n")
	}

	/// The declarations of the scope types a seam's or a public mock's own `builders` are handed, in builder order: each own
	/// root enum, with the enums nested in it, the plain root of a hole type declared before its `@Sendable` root even where
	/// it takes no builder of its own. Each `public` declaration that names a type SafeDI reads no declaration of is marked
	/// for the file's comment (`unreadTypeComment`), by its `public` fields and, where `namesForwardedTypes`, the forwarded
	/// values its cases carry.
	static func ownScopeTypeDeclarations(
		builders: [SeamSignature.Builder],
		scopeEnums: [SeamSignature.ScopeEnum],
		holes: [SeamSignature.Hole],
		typesDeclaredEscaping: Set<TypeDescription>,
		unreadTypeComment: UnreadTypeComment?,
		namesForwardedTypes: Bool,
	) -> [String] {
		guard let ownType = builders.first?.enumKey.seamType else { return [] }
		let holesBySite = Dictionary(holes.map { ($0.site, $0) }, uniquingKeysWith: { first, _ in first })
		let calledRootsTakingValue = calledRootsTakingValue(amongEnumsOf: scopeEnums, filledBy: scopeEnums.filter { $0.key.seamType == ownType })
		// Each level's form is computed once per hole type: the builder structs ask for the form of a level once for every case
		// that holds it.
		var levelFormsByHoleType = [SeamSignature.HoleType: LevelBuilderForms]()
		return scopeEnums.filter { $0.rootTypeName == nil && $0.key.seamType == ownType }.map { scopeEnum in
			let key = scopeEnum.key
			// A root enum declares the enums of its family's types other than the seam's own, nested inside it; a case spells the
			// enum it holds as its kind gives it, a root or a nested enum of either family.
			let nestedEnums = scopeEnums.filter { $0.key.describedType != nil && $0.key.seamType == key.seamType && $0.key.holeType == key.holeType && $0.key.isSendable == key.isSendable }
			var namedTypes = [TypeDescription]()
			for enumCase in ([scopeEnum] + nestedEnums).flatMap(\.cases) {
				namedTypes += enumCase.values?.fields.filter { $0.access == .public }.map(\.property.typeDescription) ?? []
				switch enumCase.kind {
				case let .place(sites):
					if namesForwardedTypes, let forwardedType = sites.first.flatMap({ holesBySite[$0] })?.forwardedType {
						namedTypes.append(forwardedType)
					}
				case .nested, .inner, .fill:
					break
				}
			}
			var levelForms = levelFormsByHoleType[key.holeType] ?? LevelBuilderForms(enumsOfHoleType: scopeEnums.filter { $0.key.holeType == key.holeType }, holesBySite: holesBySite)
			let declaration = scopeEnumDeclaration(of: scopeEnum, nestedEnums: nestedEnums, holesBySite: holesBySite, typesDeclaredEscaping: typesDeclaredEscaping, levelForms: &levelForms, calledRootsTakingValue: calledRootsTakingValue)
			levelFormsByHoleType[key.holeType] = levelForms
			guard let marker = unreadTypeComment?.markerLine(namedBy: namedTypes, indent: standardIndent) else { return declaration }
			return "\(marker)\n\(declaration)"
		}
	}

	/// The called seams' root enums, among `reachedEnums`, whose builder struct takes a builder that takes a value from its
	/// no-scope initializer, of those a case of `fillingEnums` for a builder the seam fills holds: every place such a root
	/// reaches is held in an instantiator that forwards a value (`DependencyTreeGenerator.builderForm(ofPlaces:)`), whose
	/// property ends the place's site path. Found once for the seam, never once for each case.
	private static func calledRootsTakingValue(amongEnumsOf reachedEnums: [SeamSignature.ScopeEnum], filledBy fillingEnums: [SeamSignature.ScopeEnum]) -> Set<SeamSignature.ScopeEnum.Key> {
		var innerKeys = Set<SeamSignature.ScopeEnum.Key>()
		for enumCase in fillingEnums.flatMap(\.cases) {
			if case let .fill(innerKey, _?, _, _, _) = enumCase.kind {
				innerKeys.insert(innerKey)
			}
		}
		var calledRootsTakingValue = Set<SeamSignature.ScopeEnum.Key>()
		var calledEnumsByHoleType = [SeamSignature.HoleType: [SeamSignature.ScopeEnum.Key: SeamSignature.ScopeEnum]]()
		for innerKey in innerKeys {
			if calledEnumsByHoleType[innerKey.holeType] == nil {
				calledEnumsByHoleType[innerKey.holeType] = Dictionary(reachedEnums.filter { $0.key.holeType == innerKey.holeType }.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
			}
			let places = SeamSignature.ScopeEnum.sitesReached(from: innerKey, in: calledEnumsByHoleType[innerKey.holeType] ?? [:]).compactMap(\.path.last)
			if DependencyTreeGenerator.builderForm(ofPlaceProperties: places).forwardedValue != nil {
				calledRootsTakingValue.insert(innerKey)
			}
		}
		return calledRootsTakingValue
	}

	/// The declaration of `scopeEnum`, nested in the seam or the public mock, a namespace no generated code builds or switches
	/// over a case of: each case's payload struct, in the order the generated code first reaches the cases, then, for a root
	/// enum nested by type, each of `nestedEnums`, then its builder struct. `public`, so its access is the seam's.
	/// - Parameters:
	///   - levelForms: The forms of the levels of every enum of the hole type of `scopeEnum`, both families', which decide
	///     the type each level's builder struct takes from the builder a person writes.
	///   - calledRootsTakingValue: The called seams' root enums whose struct takes a builder that takes a value from its
	///     no-scope initializer, which decide what the struct of such a root that a case for a builder the seam fills returns
	///     takes from its builder (`calledRootsTakingValue(amongEnumsOf:filledBy:)`).
	static func scopeEnumDeclaration(of scopeEnum: SeamSignature.ScopeEnum, nestedEnums: [SeamSignature.ScopeEnum] = [], holesBySite: [SeamSignature.Hole.Site: SeamSignature.Hole], typesDeclaredEscaping: Set<TypeDescription>, levelForms: inout LevelBuilderForms, calledRootsTakingValue: Set<SeamSignature.ScopeEnum.Key> = [], indent: String = standardIndent) -> String {
		let caseIndent = indent + standardIndent
		var payloadStructs = [String]()
		for enumCase in scopeEnum.cases {
			if let values = enumCase.values {
				payloadStructs.append(structDeclaration(named: values.typeName, fields: values.fields, indent: caseIndent, typesDeclaredEscaping: typesDeclaredEscaping, isNonisolated: true))
			} else if let memberValuesTypeName = enumCase.memberValuesTypeName {
				// A case that carries no values – every case of a `@Sendable` enum, and a call's case, which holds the called enum
				// alone – has a member that takes an empty `Sendable` struct.
				payloadStructs.append("\(caseIndent)nonisolated public struct \(memberValuesTypeName): Sendable {}")
			}
		}
		var body = payloadStructs.joined(separator: "\n\n")
		// Only the root declares the enums nested in it; a nested enum's cases spell them from the root.
		if scopeEnum.rootTypeName == nil {
			for nestedEnum in nestedEnums {
				body += (body.isEmpty ? "" : "\n\n") + scopeEnumDeclaration(of: nestedEnum, holesBySite: holesBySite, typesDeclaredEscaping: typesDeclaredEscaping, levelForms: &levelForms, calledRootsTakingValue: calledRootsTakingValue, indent: caseIndent)
			}
		}
		// A root of the plain family with no case of its own, a namespace for the enums its `@Sendable` root's cases hold,
		// declares no struct: no builder is handed one.
		if !scopeEnum.cases.isEmpty {
			body += (body.isEmpty ? "" : "\n\n") + builderStructDeclaration(of: scopeEnum, holesBySite: holesBySite, levelForms: &levelForms, calledRootsTakingValue: calledRootsTakingValue, indent: caseIndent)
		}
		return """
		\(indent)nonisolated public enum \(scopeEnum.typeName) {
		\(body)
		\(indent)}
		"""
	}

	/// The forms of the builders a person writes for the levels of one hole type's enums, each computed the first time a
	/// builder struct asks for it, since a level's form is asked for once for every case that holds the level.
	/// `DependencyTreeGenerator.builderForm(ofPlaces:)` reads of its places only the spellings of their wrappers and of the
	/// values they forward, never their order or how many share a spelling, so a level is handed one place per spelling its
	/// places have: reading every place of every level beneath, sorted, made the cost of a seam's enums grow with the
	/// square of its places.
	struct LevelBuilderForms {
		init(enumsOfHoleType: [SeamSignature.ScopeEnum], holesBySite: [SeamSignature.Hole.Site: SeamSignature.Hole]) {
			enumsByKey = Dictionary(enumsOfHoleType.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
			self.holesBySite = holesBySite
		}

		/// The form of the builder a person writes for the places at and beneath the level of `key`, in that level's family.
		mutating func form(ofLevel key: SeamSignature.ScopeEnum.Key) -> DependencyTreeGenerator.BuilderForm {
			if let form = formByKey[key] {
				return form
			} else {
				var placeBySpelling = [PlaceSpelling: SeamSignature.Hole]()
				var visitedKeys = Set<SeamSignature.ScopeEnum.Key>()
				var keysToVisit = [key]
				while let visitedKey = keysToVisit.popLast() {
					guard visitedKeys.insert(visitedKey).inserted, let scopeEnum = enumsByKey[visitedKey] else { continue }
					placeBySpelling.merge(ownPlaces(of: scopeEnum), uniquingKeysWith: { first, _ in first })
					for enumCase in scopeEnum.cases {
						switch enumCase.kind {
						case .place:
							break
						case let .nested(innerKey, _, _),
						     let .inner(innerKey, _, _),
						     let .fill(_, _, innerKey, _, _):
							keysToVisit.append(innerKey)
						}
					}
				}
				let form = DependencyTreeGenerator.builderForm(ofPlaces: placeBySpelling.sorted { $0.key < $1.key }.map(\.value))
				formByKey[key] = form
				return form
			}
		}

		/// Whether the no-scope initializer of the struct of the level of `key` takes a `@Sendable` builder: where the level
		/// is of the `@Sendable` family, or its initializer hands the builder to the no-scope initializer of a struct that
		/// takes one, a struct of the `@Sendable` family or a level that hands it on so. A level of the plain family whose
		/// call's case re-enters an enclosing call's fill through a builder held in a `Sendable` wrapper returns the called
		/// seam's struct of the `@Sendable` family (`SeamScopeEnumsByType.leadsToPlace(_:reenteringFills:)`), which no builder
		/// that is not `@Sendable` can make; the enclosing call's fill is then built in a `@Sendable` function, so the root
		/// that holds the level is of the `@Sendable` family and hands its own builder down.
		mutating func takesSendableBuilder(atLevel key: SeamSignature.ScopeEnum.Key) -> Bool {
			if let levelsTakingSendableBuilder {
				return levelsTakingSendableBuilder.contains(key)
			} else {
				// The levels that hold each level, from which a level that takes a `@Sendable` builder makes its holders take one.
				var holdersByKey = [SeamSignature.ScopeEnum.Key: [SeamSignature.ScopeEnum.Key]]()
				var takingKeys = Set<SeamSignature.ScopeEnum.Key>()
				for (holderKey, scopeEnum) in enumsByKey {
					// The structs the level's no-scope initializer makes: a call's case for a builder it fills makes the called
					// seam's struct around the fill's level, unless it carries no scope value.
					var heldKeys = [SeamSignature.ScopeEnum.Key]()
					for enumCase in scopeEnum.cases {
						switch enumCase.kind {
						case .place:
							break
						case let .fill(innerKey, _?, heldKey, _, _):
							heldKeys += [innerKey, heldKey]
						case let .nested(heldKey, _, _),
						     let .inner(heldKey, _, _),
						     let .fill(_, _, heldKey, _, _):
							heldKeys.append(heldKey)
						}
					}
					if holderKey.isSendable || heldKeys.contains(where: \.isSendable) {
						takingKeys.insert(holderKey)
					}
					for heldKey in heldKeys {
						holdersByKey[heldKey, default: []].append(holderKey)
					}
				}
				var keysToVisit = Array(takingKeys)
				while let visitedKey = keysToVisit.popLast() {
					for holderKey in holdersByKey[visitedKey, default: []] where takingKeys.insert(holderKey).inserted {
						keysToVisit.append(holderKey)
					}
				}
				levelsTakingSendableBuilder = takingKeys
				return takingKeys.contains(key)
			}
		}

		/// What `DependencyTreeGenerator.builderForm(ofPlaces:)` reads of a place: whether it is held in an instantiator, and
		/// then the wrapper's spelling and that of the value it forwards.
		private struct PlaceSpelling: Hashable, Comparable {
			init(of place: SeamSignature.Hole) {
				let isAnyInstantiator = place.property.propertyType.isAnyInstantiator
				self.isAnyInstantiator = isAnyInstantiator
				wrapper = isAnyInstantiator ? place.property.typeDescription.unwrapped.strippingEscaping.asSource : ""
				forwarded = isAnyInstantiator ? place.forwardedType?.strippingEscaping.asSource : nil
			}

			let isAnyInstantiator: Bool
			let wrapper: String
			let forwarded: String?

			static func < (lhs: PlaceSpelling, rhs: PlaceSpelling) -> Bool {
				(lhs.isAnyInstantiator ? 1 : 0, lhs.wrapper, lhs.forwarded ?? "") < (rhs.isAnyInstantiator ? 1 : 0, rhs.wrapper, rhs.forwarded ?? "")
			}
		}

		/// One place of each spelling among the places of `scopeEnum`'s own cases.
		private mutating func ownPlaces(of scopeEnum: SeamSignature.ScopeEnum) -> [PlaceSpelling: SeamSignature.Hole] {
			if let places = ownPlacesByKey[scopeEnum.key] {
				return places
			} else {
				var places = [PlaceSpelling: SeamSignature.Hole]()
				for enumCase in scopeEnum.cases {
					switch enumCase.kind {
					case let .place(sites):
						for place in sites.compactMap({ holesBySite[$0] }) {
							let spelling = PlaceSpelling(of: place)
							places[spelling] = places[spelling] ?? place
						}
					case .nested, .inner, .fill:
						break
					}
				}
				ownPlacesByKey[scopeEnum.key] = places
				return places
			}
		}

		private let enumsByKey: [SeamSignature.ScopeEnum.Key: SeamSignature.ScopeEnum]
		private let holesBySite: [SeamSignature.Hole.Site: SeamSignature.Hole]
		private var formByKey = [SeamSignature.ScopeEnum.Key: DependencyTreeGenerator.BuilderForm]()
		private var ownPlacesByKey = [SeamSignature.ScopeEnum.Key: [PlaceSpelling: SeamSignature.Hole]]()
		private var levelsTakingSendableBuilder: Set<SeamSignature.ScopeEnum.Key>?
	}

	/// The builder struct of `scopeEnum`, `__safeDI_Builder<Built>`, indented by `indent`: one stored function per case, its
	/// member, named as the case, which takes the struct the case's member takes (`ScopeEnum.Case.memberValuesTypeName`) and
	/// returns what the place builds – for a place held in an instantiator, the erased wrapper's `Builder` over what the place
	/// forwards, `()` for nothing, since the constrained wrappers cannot be spelled over `Built` – or the builder struct of
	/// the enum the case holds; the memberwise initializer; and `init(__safeDI_noScope:)`, which makes every member call one
	/// builder, as a seam's readable initializer passes it the builder a person wrote. That builder's type is the one a
	/// person writes for the places at and beneath the level, in the level's own family
	/// (`DependencyTreeGenerator.builderForm(ofPlaces:)`), over `Built`, or in the `@Sendable` family where the level hands
	/// it to a struct that takes a `@Sendable` one (`LevelBuilderForms.takesSendableBuilder(atLevel:)`). A member whose own
	/// type takes a value where the level's builder takes nothing – `()`, or `T.ForwardedProperties`, which is `Void` beside
	/// a place that forwards nothing – is handed the builder adapted to it. A `@Sendable` enum's struct is `Sendable`, with
	/// `@Sendable` members.
	private static func builderStructDeclaration(
		of scopeEnum: SeamSignature.ScopeEnum,
		holesBySite: [SeamSignature.Hole.Site: SeamSignature.Hole],
		levelForms: inout LevelBuilderForms,
		calledRootsTakingValue: Set<SeamSignature.ScopeEnum.Key>,
		indent: String,
	) -> String {
		let isSendable = scopeEnum.key.isSendable
		let memberIndent = indent + standardIndent
		let bodyIndent = memberIndent + standardIndent
		let sendableAttribute = isSendable ? "@Sendable " : ""
		let builtTypeName = ReservedName.builderStructGenericParameterName
		let builtType = TypeDescription.simple(name: builtTypeName, generics: [])
		let builderParameter = ReservedName.noScopeParameterName
		let levelForm = levelForms.form(ofLevel: scopeEnum.key)
		let takesSendableBuilder = levelForms.takesSendableBuilder(atLevel: scopeEnum.key)
		let noScopeType: TypeDescription = if let forwarded = levelForm.forwardedValue {
			DependencyTreeGenerator.erasedBuilderType(forwarding: forwarded, returning: builtType, isSendable: takesSendableBuilder)
		} else if takesSendableBuilder {
			TypeDescription.closure(arguments: [], isAsync: false, doesThrow: false, returnType: builtType).asSendableFunction
		} else {
			TypeDescription.closure(arguments: [], isAsync: false, doesThrow: false, returnType: builtType)
		}
		/// The builder, adapted to a member or a level beneath that takes `forwarded` where this level's takes nothing.
		func builder(adaptedTo forwarded: TypeDescription?) -> String {
			if levelForm.forwardedValue == nil, forwarded != nil {
				"{ _ in \(builderParameter)() }"
			} else {
				builderParameter
			}
		}
		var members = [(name: String, type: String, noScopeValue: String)]()
		for enumCase in scopeEnum.cases {
			let returnType: String
			let noScopeValue: String
			switch enumCase.kind {
			case let .place(sites):
				if let place = sites.first.flatMap({ holesBySite[$0] }), place.property.propertyType.isAnyInstantiator {
					let forwarded = place.forwardedType?.strippingEscaping ?? .void(.tuple)
					returnType = DependencyTreeGenerator.erasedBuilderType(forwarding: forwarded, returning: builtType, isSendable: isSendable).asSource
					noScopeValue = builder(adaptedTo: forwarded)
				} else {
					returnType = builtTypeName
					noScopeValue = "\(builderParameter)()"
				}
			case let .fill(innerKey, innerEnumType?, enumKey, enumType, _):
				// A call's case for a builder it fills returns the called seam's struct over the struct of the fill's own level:
				// its places, wherever on the called seam's levels, build the level of what the fill builds.
				returnType = "\(innerEnumType.asSource).\(ReservedName.builderStructTypeName)<\(enumType.asSource).\(ReservedName.builderStructTypeName)<\(builtTypeName)>>"
				noScopeValue = ".init(\(ReservedName.noScopeArgumentLabel): { \(calledRootsTakingValue.contains(innerKey) ? "_ in " : "").init(\(ReservedName.noScopeArgumentLabel): \(builder(adaptedTo: levelForms.form(ofLevel: enumKey).forwardedValue))) })"
			case let .nested(enumKey, enumType, _),
			     let .inner(enumKey, enumType, _),
			     let .fill(_, _, enumKey, enumType, _):
				returnType = "\(enumType.asSource).\(ReservedName.builderStructTypeName)<\(builtTypeName)>"
				noScopeValue = ".init(\(ReservedName.noScopeArgumentLabel): \(builder(adaptedTo: levelForms.form(ofLevel: enumKey).forwardedValue)))"
			}
			members.append((enumCase.name, "\(sendableAttribute)(\(enumCase.memberValuesTypeName ?? "")) -> \(returnType)", noScopeValue))
		}
		var lines = [
			"\(indent)/// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.",
			"\(indent)nonisolated public struct \(ReservedName.builderStructTypeName)<\(builtTypeName)>\(isSendable ? ": Sendable" : "") {",
		]
		// A member is named as its case, which is a label, so it is declared as a member's name is spelled: `Type` and
		// `Protocol` in backticks. No case is named `self`, which the memberwise initializer's parameter would hide the
		// instance behind: the macro requires an initializer parameter named as each dependency, and no initializer can
		// assign a property from a parameter named `self`.
		for member in members {
			lines.append("\(memberIndent)public let \(member.name.spelledAsMemberDeclarationName): \(member.type)")
		}
		lines.append("")
		lines.append("\(memberIndent)public init(\(members.map { "\($0.name): @escaping \($0.type)" }.joined(separator: ", "))) {")
		for member in members {
			lines.append("\(bodyIndent)self.\(member.name) = \(member.name)")
		}
		lines.append("\(memberIndent)}")
		lines.append("")
		lines.append("\(memberIndent)public init(\(ReservedName.noScopeArgumentLabel) \(builderParameter): @escaping \(noScopeType.asSource)) {")
		for member in members {
			lines.append("\(bodyIndent)self.\(member.name) = { _ in \(member.noScopeValue) }")
		}
		lines.append("\(memberIndent)}")
		lines.append("\(indent)}")
		return lines.joined(separator: "\n")
	}

	/// The code a seam's tree generates at a site of `property`, a hole: the member of its case called on the builder struct
	/// in scope there, handed the values in scope there. A constant is bound with its declared type, as inline binds an
	/// existential. An instantiator is built around what its member returns, the builder the wrapper keeps, with no function
	/// of the seam's own. Any other wrapper is built around a function that makes the call, as inline builds a wrapper around
	/// its builder function, which is `@Sendable` for a `Sendable` wrapper.
	/// - Parameters:
	///   - functionName: The name of that function where it differs from `functionName(toBuild:)`.
	///   - lazilyInstantiatedInstanceProperties: The by-value properties whose labels the site's owner holds only as a
	///     `LazilyInstantiated` property, whose instance the payload reads, as the owner's receivers do
	///     (`SeamHoles.valuesArguments(of:readingInstancesOf:)`).
	///   - lazilyInstantiatedBindingNames: In a public mock, the names the wrappers it binds apart from their instances' labels
	///     have where the site is built, which the payload reads a field of such a wrapper by
	///     (`SeamHoles.valuesArguments(of:readingInstancesOf:bindingNamesPassedByName:lazilyInstantiatedBindingNames:)`).
	///   - isNonisolated: Whether the tree spells a `@Sendable` local function it declares `nonisolated` too.
	// Kept out of `generatePropertyCode`'s async frame, as the functions that write a property's scope are.
	@inline(never)
	static func buildSiteCode(of property: Property, at site: SeamSignature.Hole, functionName: String?, readingInstancesOf lazilyInstantiatedInstanceProperties: Set<Property> = [], lazilyInstantiatedBindingNames: [String: [TypeDescription: String]] = [:], isNonisolated: Bool = false) -> String {
		// A place nested by type is handed what its owner binds before it; the cases that lead to it carry what each type on
		// the way binds, which the tree bound before building the next. A place in a `@Sendable` enum held in a `Sendable`
		// wrapper carries nothing.
		let fields = site.enumPlace?.values ?? site.fields
		let arguments = SeamHoles.valuesArguments(of: fields, readingInstancesOf: lazilyInstantiatedInstanceProperties, lazilyInstantiatedBindingNames: lazilyInstantiatedBindingNames)
		// The expression that builds the value: the place's member, called on the struct the last case on its route returned,
		// or on the builder itself. An instantiator's member returns the builder its wrapper keeps. Every place of a seam's or
		// a public mock's tree has its enum's case, whose member takes a struct (`SeamBuilderFamilies`). The `""` is never
		// returned: a hole is built before its place's case is known, so `enumPlace` is optional, and it is assigned to every
		// place before any code is generated; no type holds that order. 2.3.1's emitter rewrite replaces this code and drops
		// the fallback.
		guard let enumPlace = site.enumPlace, let memberValuesTypeName = enumPlace.memberValuesTypeName else { return "" }
		let valuesType = TypeDescription.nested(name: memberValuesTypeName, parentType: enumPlace.enumType(qualifiedBy: nil), generics: [])
		// Inside a fill whose call's case leads on, the fill is handed the struct of its own level.
		let lastStep = enumPlace.route.last
		let parentName = (lastStep?.member == nil ? nil : lastStep?.innerScope?.name) ?? lastStep?.member?.bindingName ?? site.internalName
		let buildExpression = "\(parentName).\(enumPlace.caseName)(\(valuesType.asSource)(\(arguments)))"
		let propertyType = property.propertyType
		guard !propertyType.isConstant else {
			return "let \(property.asSource) = \(buildExpression)"
		}
		let unwrappedType = property.typeDescription.unwrapped
		// A type constructed by annotation spells its generic arguments only in the declaration's annotation.
		let declaration = property.typeDescription.asSource == unwrappedType.spelledForConstruction ? "let \(property.label)" : "let \(property.asSource)"
		guard !propertyType.isAnyInstantiator else {
			// An instantiator's member returns the builder the wrapper keeps, which takes the forwarded value itself.
			return "\(declaration) = \(unwrappedType.spelledForConstruction)(\(buildExpression))"
		}
		let functionName = functionName ?? site.wrapperFunctionName ?? Self.functionName(toBuild: property)
		return """
		\(localFunctionPrefix(isSendable: propertyType.isSendable, isNonisolated: isNonisolated))func \(functionName)() -> \(site.builtType.asSource) {
		\(standardIndent)\(buildExpression)
		}
		\(declaration) = \(unwrappedType.spelledForConstruction)(\(functionName))
		"""
	}

	/// The name of the parameter that holds the value an instantiator forwards, in a fill of a hole's `property`: named
	/// apart from the function that builds the property, which it would hide, or be hidden by.
	private static func forwardedValueParameterName(forBuilding property: Property) -> String {
		let name = ReservedName.forwardedValueParameterName
		return functionName(toBuild: property) == name ? "\(name)_" : name
	}

	/// The function a seam's caller generates to fill the builder for `hole`: it binds the fields of the payload its case
	/// carries that the tree of its one child, the hole's property, reads, builds the property as inline builds it at the
	/// site, and returns it, or, for a wrapper, what the wrapper's builder function builds, handing that function the value
	/// an instantiator forwards. A case that carries no payload – a place held in a `Sendable` wrapper – hands the fill none.
	private func generateFillCode(
		of hole: SeamSignature.Hole,
		functionName: String,
		isSendable: Bool,
		takesPayloadFields: Bool,
		codeGeneration: CodeGeneration,
		propertiesGeneratedLater: Set<Property>,
		enclosingFunctionNames: [BuiltDeclaration: String],
		fillPlaceBindings: FillPlaceBindings,
	) async throws -> String {
		guard let child = propertiesToGenerate.first, let property = child.property else { return "" }
		// A field is bound where the tree reads it, or where a site inside the fill – one of the seam whose tree the fill
		// is generated in – carries this binding in its own struct, unless the fill reads it from the caller's scope: one bound
		// from a deferred parameter (see `fillStructBoundLabels`).
		func isRead(_ field: SeamSignature.Hole.Field) -> Bool {
			fillStructBoundLabels.contains(field.property.label)
				&& (child.reads(field.property) || child.fieldsCarriedBySites.contains(field.property))
		}
		// The parameter is named apart from what the tree reads by name, which it would hide.
		let labelsReadInFill = Set(fillFields.map(\.property.label)
			+ child.receivedProperties.map(\.label)
			+ child.fieldsCarriedBySites.map(\.label))
		var scopeParameterName = "scope"
		while labelsReadInFill.contains(scopeParameterName) {
			scopeParameterName += "_"
		}
		let indent = Self.standardIndent
		let childCode = try await generateProperties(
			codeGeneration: codeGeneration,
			propertiesGeneratedLater: propertiesGeneratedLater,
			enclosingFunctionNames: enclosingFunctionNames,
			leadingMemberWhitespace: indent,
			fillPlaceBindings: fillPlaceBindings,
		)
		// A caller's own value the fill reads from its mock root's binding is bound under its label from the name the root binds
		// it under, where that is not the label.
		var body = fillCallerReads.mockRootRebindings(rootBindingNames: fillPlaceBindings.rootBindingNames).map { "\(indent)let \($0.label) = \($0.rootBindingName)" }
		// A fill is hosted as its text until fills are planned (`.claude/rules/emission-decisions.md`).
		body += GeneratedCode.lines(childCode).spelled().split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
		guard !fillReturnsWrapperBuilder else {
			// A level function's member hands the fill of an instantiator's place each field it reads, and the fill returns the
			// builder the wrapper keeps, spelled as the wrapper's own `Builder`: a function type a value it forwards could not
			// escape from. No payload struct is in scope, so the builder captures none. Each struct of the fill's own level is
			// handed as the function the inner seam's member returns for the place, the erased wrapper's `Builder` over the
			// struct, `@Sendable` in a `@Sendable` enum, whose case carries no payload: the property's builder function calls it
			// with what it was forwarded (`innerScopesCalledWithForwardedValue`).
			let innerScopeLabels = Set(fillCallerReads.innerScopeParameters.map(\.property.label))
			let parameters = fillMemberParameterFields.map { field in
				let type = if innerScopeLabels.contains(field.property.label) {
					TypeDescription.attributed(
						DependencyTreeGenerator.erasedBuilderType(
							forwarding: hole.forwardedType?.strippingEscaping ?? .void(.tuple),
							returning: field.property.typeDescription,
							isSendable: hole.enumPlace?.isBuiltBySendableBuilder ?? false,
						),
						specifiers: [],
						attributes: ["escaping"],
					)
				} else {
					field.boundTypeAsFunctionParameter(amongTypesDeclaredEscaping: typesDeclaredEscaping)
				}
				return "\(field.property.label.spelledAsArgumentLabel): \(type.asSource)"
			}
			let builderType = TypeDescription.nested(name: Dependency.wrapperBuilderTypeName, parentType: hole.property.typeDescription.unwrapped, generics: [])
			return (["\(Self.localFunctionPrefix(isSendable: isSendable, isNonisolated: true))func \(functionName)(\(parameters.joined(separator: ", "))) -> \(builderType.asSource) {"]
				+ body
				+ ["}"]).joined(separator: "\n")
		}
		// A wrapper's scope returns what its builder function builds, and a constant's has bound it.
		if property.propertyType.isConstant {
			body.append(indent + "return \(property.label)")
		}
		guard !takesPayloadFields else {
			// An override closure of the call calls the fill with the values the call passes the called mock, and a level
			// function's member with its payload's, each by itself: no other module can make the payload.
			let parameters = fillMemberParameterFields(takingPayloadFields: true).map { "\($0.property.label.spelledAsArgumentLabel): \($0.property.typeDescription.asFunctionParameter(amongTypesDeclaredEscaping: typesDeclaredEscaping).asSource)" }
			return (["\(isSendable ? "@Sendable " : "")func \(functionName)(\(parameters.joined(separator: ", "))) -> \(hole.builtType.asSource) {"]
				+ body
				+ ["}"]).joined(separator: "\n")
		}
		// A fill of a place nested by type binds what its case's payload holds, and takes what a type further out binds.
		let nestedByTypeValues = hole.enumPlace?.values
		let valuesType = hole.valuesType(qualifiedBy: hole.scopeSeamType)
		// A deferred parameter's field the fill binds from the struct is bound as its memo (`bindingItsMemo`).
		let memoBoundLabels = Set(fillFields.filter(\.bindsMemo).map(\.property.label))
		let bindings = valuesType == nil ? [] : (nestedByTypeValues ?? hole.fields).filter(isRead).map { "\(indent)let \($0.property.label) = \(scopeParameterName).\($0.memberName(bindingMemo: memoBoundLabels.contains($0.property.label)))" }
		// A fill of an instantiator's place returns the wrapper's builder (`fillReturnsWrapperBuilder`), so no fill here takes
		// a forwarded value.
		var parameters = valuesType.map { ["_ \(scopeParameterName): \($0.asSource)"] } ?? []
		parameters += fillParameterFields.map { "\($0.property.label.spelledAsArgumentLabel): \($0.boundTypeAsFunctionParameter(amongTypesDeclaredEscaping: typesDeclaredEscaping).asSource)" }
		return (["\(isSendable ? "@Sendable " : "")func \(functionName)(\(parameters.joined(separator: ", "))) -> \(hole.builtType.asSource) {"]
			+ bindings
			+ body
			+ ["}"]).joined(separator: "\n")
	}

	/// Whether `fill`, a child of this scope, a fill of its seam call, builds its tree inside a `@Sendable` function: its
	/// own (`sendableFills(of:referencedFromSendableFunctions:)`). `false` for a generator that is no fill. Every reader of
	/// whether a fill is `@Sendable` – generation, the capture walk, a seam's signature, and the walk of what its tree reads
	/// – asks here.
	nonisolated func buildsInSendableFunction(ofFill fill: ScopeGenerator) -> Bool {
		guard fill.fillHole != nil else { return false }
		return fill.fillKey.map(sendableFillKeys.contains) ?? false
	}

	/// A fill or dispatcher of one seam call, as the walk of which are `@Sendable` sees it.
	private struct SendableFillNode {
		let key: String
		/// The keys of the fills and dispatchers it refers to.
		let references: Set<String>
		let startsSendable: Bool
	}

	/// The fills and dispatchers among `fills`, those of one seam call, whose first function is `@Sendable`, by key, and every
	/// fill or dispatcher of an enclosing call that those functions refer to. One is `@Sendable` when a `@Sendable`-family
	/// argument of the call reaches it (`startsSendable`), a `@Sendable` function that does not enclose it refers to it or
	/// passes it to a seam that takes it `@Sendable` (`referencedFromSendableFunctions`, found beneath this call), or such a
	/// function, fill or dispatcher refers to it: one made `@Sendable` is a `@Sendable` function that refers to what it
	/// refers to. The set only grows, so it is found with a worklist; it reads this call's subtree and the settled signatures
	/// of the seams the subtree calls, and so no seam's own signature can depend on itself through it.
	private static func sendableFills(
		of fills: [SendableFillNode],
		referencedFromSendableFunctions: Set<String>,
	) -> (keys: Set<String>, referencedFillKeys: Set<String>) {
		var fillsToVisit = fills.filter { $0.startsSendable || referencedFromSendableFunctions.contains($0.key) }
		var keys = Set(fillsToVisit.map(\.key))
		var referencedFillKeys = Set<String>()
		while let fill = fillsToVisit.popLast() {
			referencedFillKeys.formUnion(fill.references)
			for referencedFill in fills where fill.references.contains(referencedFill.key) && keys.insert(referencedFill.key).inserted {
				fillsToVisit.append(referencedFill)
			}
		}
		return (keys, referencedFillKeys)
	}

	/// The initializers a seam's module generates for the seam, followed by the enum every generated call refers to. Each
	/// tier has one only generated code calls, whose labels are prefixed, and which every generated call calls; when the
	/// seam's module sets `generatePlainDependencyTreeInitializers`, it is preceded by a plain one for people, whose
	/// parameters are values under readable labels and whose body forwards them. A tier's initializer only generated
	/// code calls passes `nil` for the parameters the tier omits and calls the next narrower tier's; the narrowest builds
	/// the tree and calls the seam's own initializer.
	private func generateSeamRootCode(
		instantiable: Instantiable,
		seamRoot: SeamRoot,
		unavailableProperties: Set<Property>,
		propertiesGeneratedLater: Set<Property>,
		builderFunctionNames: BuilderFunctionNames,
		fillPlaceBindings: FillPlaceBindings,
	) async throws -> String {
		let signature = seamRoot.signature
		let typeName = instantiable.concreteInstantiable.asSource
		let initializerKeyword = "\(instantiable.declarationType == .classType ? "convenience " : "")init"
		let bodyIndent = "\(Self.standardIndent)\(Self.standardIndent)"
		// Every initializer carries the attributes a root's generated `init()` carries: a caller can reach any of them,
		// and each calls another.
		let attributesPrefix = instantiable.generatedInitializerAttributes.isEmpty ? "" : "\(instantiable.generatedInitializerAttributes) "
		// Every tier takes every builder, after its parameters: a hole is required. Each tier takes a builder under its own
		// label (`SeamSignature.Builder.narrowerTierLabels`). An initializer people call declares no underscored name, which
		// would keep it out of the module's symbol graph.
		func plainBuilderParameters(inTierAt tier: AccessLevel) -> [String] {
			signature.builders.map { "\($0.label(inTierAt: tier).spelledAsArgumentLabel): \($0.readableParameterType.asSource)" }
		}
		func generatedOnlyBuilderParameters(inTierAt tier: AccessLevel) -> [String] {
			signature.builders.map { builder in
				let label = builder.generatedOnlyArgumentLabel(inTierAt: tier)
				return "\(builder.internalName == label ? builder.internalName : "\(label) \(builder.internalName)"): \(builder.parameterType.asSource)"
			}
		}
		// No parameter has a default: every call writes every argument, so a hand-written call fails to compile when the
		// tree comes to take another parameter, rather than passing `nil` for it.
		func plainParameterList(of parameters: [SeamSignature.Parameter], inTierAt tier: AccessLevel) -> String {
			(parameters.map { $0.plainSpelling(amongTypesDeclaredEscaping: typesDeclaredEscaping) } + plainBuilderParameters(inTierAt: tier)).joined(separator: ", ")
		}
		func generatedOnlyParameterList(of parameters: [SeamSignature.Parameter], inTierAt tier: AccessLevel) -> String {
			(parameters.map { $0.generatedOnlySpelling(amongTypesDeclaredEscaping: typesDeclaredEscaping) } + generatedOnlyBuilderParameters(inTierAt: tier)).joined(separator: ", ")
		}
		// The narrowest tier holds each deferred parameter in a `LazilyInstantiated` under its label, which the tree reads
		// wherever it reads the label, in parameter order – except a parameter the seam's own alias of its label reads.
		let autoclosureCallByLabel = seamRoot.autoclosureCallByLabel(of: instantiable)
		let memoLines = signature.parameters.compactMap { parameter -> String? in
			guard case let .deferred(isSendable) = parameter.deferral, autoclosureCallByLabel[parameter.property.label] == nil else { return nil }
			let wrapperType = TypeDescription.simple(
				name: isSendable ? Dependency.sendableLazilyInstantiatedType : Dependency.lazilyInstantiatedType,
				generics: [parameter.property.typeDescription],
			)
			return "\(bodyIndent)let \(parameter.property.label) = \(wrapperType.asSource)(\(parameter.internalName))"
		}
		let tierParameters = signature.tiers.map(signature.parameters(ofTierAt:))
		var initializers = [String]()
		for (index, tier) in signature.tiers.enumerated() {
			let parameters = tierParameters[index]
			let body: String
			if index == signature.tiers.count - 1 {
				// The narrowest tier builds the tree, which reads each builder by its internal name, its parameter's name.
				let generatedProperties = try await generateProperties(
					propertiesGeneratedLater: propertiesGeneratedLater,
					enclosingFunctionNames: builderFunctionNames.enclosingFunctionNames,
					leadingMemberWhitespace: bodyIndent,
					fillPlaceBindings: fillPlaceBindings,
				)
				let argumentList = try instantiable.generateArgumentList(
					unavailableProperties: unavailableProperties,
				)
				// A seam's root is hosted as its text until seam bodies are planned (`.claude/rules/emission-decisions.md`).
				var bodyLines = memoLines
				if !generatedProperties.isEmpty {
					bodyLines.append(GeneratedCode.lines(generatedProperties).spelled())
				}
				bodyLines.append("\(bodyIndent)self.init(\(argumentList))")
				body = bodyLines.joined(separator: "\n")
			} else {
				// A wider tier passes `nil` for each parameter it omits: one whose type the tier's callers cannot
				// see, which only a parameter received only if available can be. It passes a deferred parameter it takes
				// as its autoclosure's call, which the narrower tier's autoclosure defers in turn.
				let tierParameterSet = Set(parameters.map(\.property))
				let parameterArguments = tierParameters[index + 1].map { parameter in
					let value = if !tierParameterSet.contains(parameter.property) {
						"nil"
					} else if parameter.isDeferred {
						"\(parameter.internalName)()"
					} else {
						parameter.property.label
					}
					return "\(parameter.generatedOnlyArgumentLabel): \(value)"
				}
				let narrowerTier = signature.tiers[index + 1]
				let builderArguments = signature.builders.map { "\($0.generatedOnlyArgumentLabel(inTierAt: narrowerTier)): \($0.internalName)" }
				body = "\(bodyIndent)self.init(\((parameterArguments + builderArguments).joined(separator: ", ")))"
			}
			let marker = tier == .public
				? seamRoot.unreadTypeComment?.markerLine(namedBy: parameters.map(\.property.typeDescription) + signature.holes.map(\.property.typeDescription), indent: Self.standardIndent).map { "\($0)\n" }
				: nil
			// Each initializer has the type's isolation, or the one `generatedInitializerAttributes` spells, never the seam's own
			// initializer's: it builds the tree, whose isolation the own initializer, which only stores built values, does not
			// tell. A deliberate gap against the tree built in one module, where the caller's isolation builds it.
			let declarationPrefix = "\(Self.standardIndent)\(attributesPrefix)\(tier.spelledOnGeneratedDeclaration) \(initializerKeyword)"
			// A builder the caller passes can be held by a wrapper the seam builds, such as an instantiator, and called later.
			let plainDocumentation = if signature.builders.isEmpty {
				"\(Self.standardIndent)/// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained."
			} else {
				"\(Self.standardIndent)/// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns."
			}
			// A tier that takes no argument has one initializer, `init()`, which the two would both spell and which code of
			// either kind can call, whatever the setting. Otherwise the initializer only generated code calls points code
			// people write at the plain one above it where the module generates it, and at the setting where it does not.
			let takesNoArgument = parameters.isEmpty && signature.builders.isEmpty
			let generatedOnlyDocumentation = if takesNoArgument {
				"\(Self.standardIndent)/// Code you write and code SafeDI generates can both call this initializer."
			} else if seamRoot.generatesPlainInitializers {
				"""
				\(Self.standardIndent)/// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				\(Self.standardIndent)/// From code you write, call the initializer above instead.
				"""
			} else {
				"""
				\(Self.standardIndent)/// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				\(Self.standardIndent)/// To call this type from code you write, set `\(SafeDIConfigurationVisitor.generatePlainDependencyTreeInitializersArgumentLabel): true` in this module’s `#\(SafeDIConfigurationVisitor.macroName)`.
				"""
			}
			let generatedOnlyInitializer = """
			\(generatedOnlyDocumentation)
			\(declarationPrefix)(\(generatedOnlyParameterList(of: parameters, inTierAt: tier))) {
			\(body)
			\(Self.standardIndent)}
			"""
			if seamRoot.generatesPlainInitializers, !takesNoArgument {
				// The plain initializer forwards its values, so the closures the other one holds capture its own parameters
				// and never what its caller wrote.
				// A builder that takes nothing is handed to the generated-only initializer as a builder struct every member of which
				// calls it.
				let forwardedArguments = parameters.map { "\($0.generatedOnlyArgumentLabel): \($0.property.label)" }
					+ signature.builders.map { builder in
						let label = builder.label(inTierAt: tier)
						let argument = ".init(\(ReservedName.noScopeArgumentLabel): \(label))"
						return "\(builder.generatedOnlyArgumentLabel(inTierAt: tier)): \(argument)"
					}
				initializers.append("""
				\(marker ?? "")\(plainDocumentation)
				\(declarationPrefix)(\(plainParameterList(of: parameters, inTierAt: tier))) {
				\(bodyIndent)self.init(\(forwardedArguments.joined(separator: ", ")))
				\(Self.standardIndent)}
				""")
				initializers.append(generatedOnlyInitializer)
			} else {
				initializers.append((marker ?? "") + generatedOnlyInitializer)
			}
		}
		// The scope types of the seam's builders before the initializers that build them. A case's forwarded value is as
		// visible as the enum, which is spelled `public` but is no wider than the seam.
		let scopeTypes = Self.ownScopeTypeDeclarations(
			builders: signature.builders,
			scopeEnums: signature.scopeEnums,
			holes: signature.holes,
			typesDeclaredEscaping: typesDeclaredEscaping,
			unreadTypeComment: seamRoot.unreadTypeComment,
			namesForwardedTypes: signature.tiers.first == .public,
		)
		// The class each of the tree's boxes is, after the initializers, in the order of their names (`boxedLoops`).
		var members = scopeTypes + initializers
		for (_, declaration) in loopLevelsTypesInTree.sorted(by: { $0.key < $1.key }) {
			members.append(declaration)
		}
		return """
		extension \(typeName) {
		\(members.joined(separator: "\n\n"))
		}

		\(Self.guardEnumDeclaration(extending: typeName, named: signature.guardTypeName))
		"""
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
		"let \(property.asSource) = \(aliasValue(of: property, fulfilledBy: fulfillingExpression, ofType: fulfillingTypeDescription, erasedToConcreteExistential: erasedToConcreteExistential, fulfillingValueMayBeOptional: fulfillingValueMayBeOptional))"
	}

	/// The value an alias of `property` is bound to from `fulfillingExpression`: that expression, or, for an erased
	/// alias, the existential wrapping it, mapped over an optional value where the expression may be `nil`.
	///
	/// An erased alias of a dependency declared optional (`ofType: Secret?.self`) is always mapped, required or
	/// `onlyIfAvailable`, whatever binding it reads: a forwarded optional, a mock's optional parameter or override, or
	/// the non-optional value a required `token: Secret?` resolves to. It is `nil` where the dependency is, and
	/// `(token as Secret?).map { AnyAuth($0) }` compiles over `Secret` and `Secret?` alike, so production, mocks, and
	/// seams bind it with one expression. Never decide the wrapping from the binding alone.
	private static func aliasValue(
		of property: Property,
		fulfilledBy fulfillingExpression: String,
		ofType fulfillingTypeDescription: TypeDescription,
		erasedToConcreteExistential: Bool,
		fulfillingValueMayBeOptional: Bool,
	) -> String {
		let existentialTypeSource = property.typeDescription.unwrapped.asSource
		return if !erasedToConcreteExistential {
			fulfillingExpression
		} else if fulfillingValueMayBeOptional || fulfillingTypeDescription.isOptional {
			// The fulfilling type's optional form, spelled once: an alias of a property declared optional (`ofType:
			// Secret?.self`) maps over `Secret?`, never `Secret??`.
			"(\(fulfillingExpression) as \(fulfillingTypeDescription.isOptional ? fulfillingTypeDescription.asSource : TypeDescription.optional(fulfillingTypeDescription).asSource)).map { \(existentialTypeSource)($0) }"
		} else {
			"\(existentialTypeSource)(\(fulfillingExpression))"
		}
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

	/// The hand-written mock a flat parameter of `mock()` – a `@Forwarded` property of the mocked type, or a received
	/// dependency the mock cannot build – defaults to: the one the mock scope map builds a property of the parameter's
	/// type with, when it takes no required argument and the module generating the mock can call it
	/// (`DependencyTreeGenerator.flatParameterMockDefaults(in:emittingModule:)`).
	struct FlatParameterMockDefault: Sendable {
		/// The concrete type whose hand-written mock the default calls.
		let concreteType: TypeDescription
		/// The name of the hand-written mock: `customMockName`, or `mock`.
		let methodName: String
		/// The file that declares the hand-written mock.
		let mockFilePath: String?
		/// The types the default names that the parameter's declaration does not, in modules other than the one the mock
		/// compiles in.
		let fulfillers: Set<FulfillerImports.Fulfiller>

		/// The call of the hand-written mock that takes no argument.
		var expression: String {
			"\(concreteType.asSource).\(methodName)()"
		}
	}

	/// The default value of a `@Forwarded` parameter of `mock()`.
	enum ForwardedParameterDefault {
		/// The default value of the parameter of the mocked type's construction with the forwarded property's label.
		case constructionDefault(String)
		/// The hand-written mock of the forwarded type.
		case handWrittenMock(FlatParameterMockDefault)

		/// The parameter's default expression.
		var expression: String {
			switch self {
			case let .constructionDefault(expression):
				expression
			case let .handWrittenMock(mockDefault):
				mockDefault.expression
			}
		}
	}

	/// The parameters a mock root's `mock()` takes, before the labels of flat parameters that collide are
	/// named apart. `generateMockRootCode` emits them; `DependencyTreeGenerator.mockRequirements(forTypeNamed:)`
	/// reports them.
	struct MockRootParameters {
		/// The mock root's parameter tree: the dependencies the mock builds, which `SafeDIOverrides` can override.
		let parameterTree: [MockTreeItem]
		/// The name of each property node of `parameterTree`'s root level, by label and property type: its label,
		/// unless a sibling or a `@Forwarded` or default-valued parameter of `mock()` shares the label. See
		/// `disambiguatePropertyLabels`.
		let rootLabelMap: [String: [TypeDescription: String]]
		/// The mocked type's `@Forwarded` dependencies, in the order they are parameters of `mock()`.
		let forwardedDependencies: [Dependency]
		/// The default of each of `forwardedDependencies` that has one, by label: the default `rootConstructionInitializer`
		/// gives the parameter of its label, else the hand-written mock of its type.
		let forwardedParameterDefaults: [String: ForwardedParameterDefault]
		/// The initializer the mock constructs the mocked type with: its hand-written mock when it has one.
		let rootConstructionInitializer: Initializer?
		/// The non-dependency parameters of `rootConstructionInitializer` that have defaults.
		let rootDefaultParameters: [RootDefaultParameter]
		/// The received properties the mock cannot build, as the caller of `mock()` provides them: by value.
		let flatReceivedProperties: [Property]
		/// The hand-written mock each of `flatReceivedProperties` whose type has one defaults to.
		let flatReceivedParameterMockDefaults: [Property: FlatParameterMockDefault]
		/// The received properties every receiver receives only if available and nothing in the mock provides.
		let onlyIfAvailableReceivedProperties: [Property]
		/// The `@Instantiated` dependencies, of the mocked type and of the types in its tree, that no node builds, but those a
		/// builder of `seamMockBuilders` builds.
		let flatUncoveredParameters: [UncoveredParameter]
		/// For the internal mock of a type that generates its dependency tree, the builders `mock()` takes in place of the
		/// parameters of the places they build (`ScopeGenerator.seamMockBuilders(of:uncoveredDependencies:otherParameterLabels:treePropertyNodes:namesBoundInTheTree:)`).
		let seamMockBuilders: [SeamMockBuilder]
		/// The lazily instantiated dependencies the tree receives and the mock cannot build.
		let lazilyInstantiatedReceivedProperties: [Property]
		/// The `LazilyInstantiated`, among `lazilyInstantiatedReceivedProperties`, that each entry of
		/// `flatReceivedProperties` or `onlyIfAvailableReceivedProperties` is the instance of, for the entries whose label
		/// and type a forwarded property of the mocked type has. Such an entry is named after its `LazilyInstantiated`,
		/// and no receive of the forwarded property is passed it.
		let lazilyInstantiatedPropertyByInstanceBesideForwardedProperty: [Property: Property]
		/// For a public mock, the wrapper it takes in place of each entry of `flatReceivedProperties` or
		/// `onlyIfAvailableReceivedProperties` that is the instance of a `LazilyInstantiated` or `SendableLazilyInstantiated`
		/// its tree receives (`publicMockWrapperParameters(…)`), keyed by that entry. Empty for an internal mock.
		let publicMockWrapperParameterByInstance: [Property: Property]
		/// The properties only the calls of other modules' public mocks in the tree receive that the mock takes no
		/// parameter or override for (`receivedOnlyByPublicMockCallsLeftOut`).
		let receivedOnlyByPublicMockCallsLeftOut: Set<Property>
		/// `ScopeGenerator.typesDeclaredEscaping` of the mock root.
		let typesDeclaredEscaping: Set<TypeDescription>
		/// For a public mock, the builders `mock()` takes (`ScopeGenerator.mockBuilders`); `nil` for a mock that takes none.
		let mockBuilders: DependencyTreeGenerator.ShapedBuilders?

		struct RootDefaultParameter {
			let label: String
			let typeSource: String
			let defaultExpression: String
			/// The parameter's type, without `@escaping`.
			let typeDescription: TypeDescription
		}

		/// A builder the internal mock of a type that generates its dependency tree takes for one hole type in one family, as
		/// the type's readable initializer does: the builder a person writes, which the builder function of each type that
		/// instantiates a place of it calls once per build, or builds the place's wrapper around, as the type's own tree calls
		/// the builder its initializer takes. The mock builds every seam inline, so it hands no struct on. An internal mock whose
		/// tree calls other modules' public mocks takes one too for each hole type and family those calls pass up, as its
		/// production tree's initializer takes one, which the calls are handed.
		struct SeamMockBuilder {
			/// The parameter's label.
			let label: String
			/// The name the body calls the builder by: `label`, or a name apart where a binding of the tree has the label.
			var internalName: String
			let family: Family
			/// The uncovered dependencies the builder builds, which `mock()` takes no parameter for.
			let places: [UncoveredParameter]
			/// The places inside the fills of the tree's calls of other modules' public mocks the builder builds (`FillPlace`).
			let fillPlaces: [FillPlace]
			/// The received properties under which the tree's calls of other modules' public mocks pass a builder of the same
			/// hole type and family up, in any form, which `mock()` takes no parameter for: the calls are handed this builder,
			/// or, where a call's form takes a value this builder does not, an adapter of it (`adapters`).
			let passedUpProperties: [Property]
			/// The parameter's type, the type the twin's builder of these places and of the places the calls pass up takes
			/// from a person.
			let parameterType: TypeDescription
			/// The adapters of the builder to the passed-up properties whose form takes a value it does not take.
			var adapters = [PassedUpAdapter]()

			/// A local `mock()` binds before its tree, the builder adapted to a call that passes it up in a form that takes a
			/// value, `T.ForwardedProperties`, where the builder takes nothing: the call is handed the adapter, which calls
			/// the builder and drops the value.
			struct PassedUpAdapter {
				/// The passed-up property the adapter stands in for.
				let property: Property
				/// The name `mock()` binds the adapter under.
				let name: String
				/// The adapter's type, as the call passes the builder up, `@Sendable` where a `@Sendable` function captures it.
				let typeDescription: TypeDescription
			}

			/// A builder a call of another module's public mock passes up, which the mock takes as one of its own builders.
			struct PassedUpBuilder {
				let family: Family
				/// The builders of the called mocks the passed-up property stands for, each with what its mock's builders reach.
				var calledBuilders = [(builder: SeamSignature.Builder, calledBuilders: CalledBuilders)]()

				/// The properties of the places the called builders reach, in the order of the calls and of each called mock's
				/// holes, which decide, with the mock's own places, the form of a builder that takes the calls' builders where
				/// they pass it up in other forms.
				var placeProperties: [Property] {
					calledBuilders.flatMap { called in
						let sites = called.calledBuilders.sitesReached(by: called.builder, in: called.calledBuilders.enumsByKey)
						return called.calledBuilders.holes.filter { sites.contains($0.site) && $0.holeType == called.builder.enumKey.holeType }.map(\.property)
					}
				}
			}

			/// The type a seam's builder of the places of `placeProperties` in `family` takes from a person
			/// (`DependencyTreeGenerator.builderForm(ofPlaceProperties:)`): a closure that takes nothing and returns what the
			/// builder builds, as the first place spells it, `@Sendable` in the `@Sendable` family, or, where every place is an
			/// instantiator, the `Builder` of its wrapper.
			static func parameterType(ofPlaceProperties placeProperties: [Property], in family: Family) -> TypeDescription {
				DependencyTreeGenerator.readableBuilderType(
					of: DependencyTreeGenerator.builderForm(ofPlaceProperties: placeProperties),
					returning: placeProperties.first?.typeDescription.builtTypeOfWrapper ?? family.holeType.builtType,
					isSendable: family.isSendable,
				)
			}

			/// A hole type, and whether its places are built inside a `@Sendable` function or held in a `Sendable` wrapper,
			/// whose builder the seam takes in its `@Sendable` family.
			struct Family: Hashable {
				let holeType: SeamSignature.HoleType
				let isSendable: Bool

				init(holeType: SeamSignature.HoleType, isSendable: Bool) {
					self.holeType = holeType
					self.isSendable = isSendable
				}

				/// The family of a place inside a fill (`FillPlace`): the `@Sendable` one where the place is bound inside a
				/// `@Sendable` function or held in a `Sendable` wrapper, as for a place of the type's own tree.
				init(of fillPlace: FillPlace) {
					let property = fillPlace.dependency.property
					self.init(
						holeType: SeamSignature.HoleType(instantiatedType: fillPlace.dependency.asInstantiatedType.spelledCanonically, builtType: property.typeDescription.builtTypeOfWrapper.spelledCanonically),
						isSendable: fillPlace.isInsideSendableFunction || property.propertyType.isSendable,
					)
				}
			}
		}

		struct UncoveredParameter {
			/// The dependency's property.
			let property: Property
			/// The parameter's name, the dependency's label unless it is named apart from another name in scope.
			let label: String
			/// The type of the value the caller passes, which `mock()` spells as the parameter's type unless
			/// `isSendableAutoclosure`.
			let typeSource: String
			/// The type the dependency instantiates, which no `@Instantiable` declaration fulfills.
			let instantiatedType: TypeDescription
			/// Whether `mock()` takes the parameter as `@autoclosure @escaping @Sendable () -> T`, because a type
			/// built inside a `@Sendable` builder function instantiates the dependency: that function cannot
			/// capture the value when its type is not `Sendable`, and SafeDI cannot tell whether it is, so each
			/// type that instantiates the dependency calls the closure where it is built
			/// (`sendableAutoclosureBindings(for:parameters:indent:)`), which creates the value once per
			/// construction, as production does. The caller still passes a value.
			let isSendableAutoclosure: Bool
			/// The types that create the dependency, each once (`typesCreatingDependencies`).
			let creatingTypes: [TypeDescription]

			/// The lines that document, above `mock()`, a parameter whose one value is handed to several types that each
			/// create the dependency in the app; none for a parameter that one type creates, or for a `@Sendable`
			/// autoclosure, which each type calls for a value of its own. Swift reads a parameter's documented name as
			/// plain text and a code span ends at a backtick, so neither name is spelled with backticks. The lines offer only
			/// a `mockOnly` fake: `safeDIOverrides` has no entry for the mocked type or for a type built beneath a `cycleEdges`
			/// edge, and an override of a type leaves the types beneath it that receive the dependency holding this parameter.
			var sharedValueDocumentation: [String] {
				guard !isSendableAutoclosure, creatingTypes.count > 1 else { return [] }
				let creatingProperties = creatingTypes.map { creatingType in
					"`\("\(creatingType.asSource).\(property.label)".spelledWithoutBackticks)`"
				}
				return [
					"/// - Parameter \(label.spelledWithoutBackticks): Passed to every type that creates this dependency:",
					"///   \(creatingProperties.joinedAsList). The app creates one for each.",
					"///   To give each its own, declare a `mockOnly` fake.",
				]
			}
		}
	}

	/// A `mock()` parameter taken as a `@Sendable` autoclosure (`MockRootParameters.UncoveredParameter.isSendableAutoclosure`),
	/// keyed by its dependency's property where it is passed to the body generators.
	///
	/// The internal mock of a type that generates its dependency tree calls each of its builders the same way
	/// (`MockRootParameters.SeamMockBuilder`), for every place the builder builds.
	struct SendableAutoclosureParameter: Hashable {
		init(name: String, localName: String, valueType: TypeDescription? = nil) {
			self.name = name
			self.localName = localName
			self.valueType = valueType
		}

		/// The parameter's name, `UncoveredParameter.label`.
		let name: String
		/// The name of the local the body reads the closure into before any builder function, so that the binding
		/// of the value under `name` in a scope that instantiates the dependency can call the closure however the
		/// scopes around it bind `name`: `__safeDI_<name>`. The prefix keeps it out of the labels SafeDI is given, and
		/// no builder function in scope has the name, since `name` is apart from every binding in the mock. For a seam's
		/// builder, the name its mock calls it by.
		let localName: String
		/// For a place a seam's builder builds, the type the binding is declared with: the place's.
		let valueType: TypeDescription?

		/// The line that binds the value where the dependency is instantiated: a wrapper, an instantiator or a
		/// `LazilyInstantiated`, is built around the builder, which it calls once per instantiation or when it is first read.
		var binding: String {
			if let valueType, !valueType.propertyType.isConstant {
				"let \(name) = \(valueType.asSource)(\(localName))"
			} else {
				"let \(name)\(valueType.map { ": \($0.asSource)" } ?? "") = \(localName)()"
			}
		}
	}

	/// A place of an internal mock inside a fill of its tree's call of another module's public mock: an `@Instantiated`
	/// dependency of a type the fill's tree builds that no scope builds, nothing the module sees fulfilling it, whose
	/// spelling can be a hole (`DependencyTreeGenerator.canBeHole`). The mock binds it from a builder it takes
	/// (`MockRootParameters.SeamMockBuilder`), as a seam's internal mock binds its hole, where the twin's fill calls the
	/// builder its seam initializer takes.
	struct FillPlace {
		/// The generator of the type that instantiates the place, whose builder function binds it.
		let generator: ObjectIdentifier
		let dependency: Dependency
		/// Whether the place is bound inside a `@Sendable` function: the fill's, or a builder function in or around it.
		let isInsideSendableFunction: Bool
		/// The place's position in the walk that found it (`fillPlaces(insideSendableFunction:)`), which orders the bindings
		/// of one type as it declares the places.
		let order: Int
	}

	/// The bindings of the places inside the fills an internal mock declares (`FillPlace`), by the generator of the type
	/// that instantiates them, in the order the type declares them: each calls the builder `mock()` takes for the place's
	/// hole type and family, once per build of the type.
	/// Also the names a mock root binds received values under apart from their labels.
	struct FillPlaceBindings: Hashable {
		init(bindingsByGenerator: [ObjectIdentifier: [SendableAutoclosureParameter]], rootBindingNames: [String: [TypeDescription: String]] = [:]) {
			self.bindingsByGenerator = bindingsByGenerator
			self.rootBindingNames = rootBindingNames
		}

		let bindingsByGenerator: [ObjectIdentifier: [SendableAutoclosureParameter]]
		/// The name the mock root binds each property it binds apart from its label under, by label and type: a flat
		/// parameter, an override, a promoted dependency, or a `LazilyInstantiated` it wraps a parameter in. A fill that reads
		/// the caller's own value from the root's binding binds the label to that name (`FillCallerReads.mockRootBindingByLabel`).
		let rootBindingNames: [String: [TypeDescription: String]]

		static let none = FillPlaceBindings(bindingsByGenerator: [:])
	}

	/// The names of a mock root's flat parameters, which its `mock()` and a public mock's signature share. See
	/// `mockRootParameterNames(of:)`.
	struct MockRootParameterNames {
		/// The names of the tree's bindings at the mock root's level.
		let treeBindingNames: Set<String>
		/// The names the builder functions beneath the mock root's level declare, which no parameter takes.
		let namesDeclaredInBuilderFunctions: Set<String>
		/// The labels of the forwarded, default-valued, uncovered and only-if-available parameters, which keep them.
		let otherFlatLabels: [String]
		/// The name of each of `MockRootParameters.flatReceivedProperties`, in order.
		let flatReceivedNames: [String]
		/// The `onlyIfAvailable` received properties nothing in the mock provides, each with its name.
		let onlyIfAvailableOverrides: [OnlyIfAvailableOverride]
	}

	/// The properties only the calls of other modules' public mocks in a mock's tree receive that the mock takes no
	/// parameter or override for: every one of them, unless the mocked type's mock is public, which takes those a call
	/// passes and leaves out only those every call omits.
	static func receivedOnlyByPublicMockCallsLeftOut(receivedOnlyByPublicMockCalls: Set<Property>, passedByPublicMockCalls: Set<Property>, mockedType: Instantiable) -> Set<Property> {
		mockedType.generateMock == .public
			? receivedOnlyByPublicMockCalls.subtracting(passedByPublicMockCalls)
			: receivedOnlyByPublicMockCalls
	}

	/// The names of the flat parameters of a mock root with `parameters`.
	static func mockRootParameterNames(of parameters: MockRootParameters) -> MockRootParameterNames {
		let treePropertyNodes = parameters.parameterTree.propertyNodes
		let namesDeclaredInBuilderFunctions = Self.namesDeclaredInBuilderFunctions(of: treePropertyNodes)
		let treeBindingNames = Self.bindingNames(of: treePropertyNodes, labels: Set(treePropertyNodes.map(\.propertyLabel)), labelMap: parameters.rootLabelMap)
		let uncoveredDependencyNames = parameters.flatUncoveredParameters.map(\.label)
		// Disambiguate flat received parameter labels when collisions exist.
		// Include onlyIfAvailable labels so flat params with the same label
		// get disambiguated: an onlyIfAvailable override keeps its label over
		// a flat received parameter.
		// Forwarded parameters keep their original labels (must match init signature).
		// A flat received parameter is named apart from the root's tree bindings too: a tree node with
		// its label and another type does not provide it, and the parameter would be hidden by it.
		var otherFlatLabels = parameters.forwardedDependencies.map(\.property.label)
			+ parameters.rootDefaultParameters.map(\.label)
		otherFlatLabels += uncoveredDependencyNames
			+ parameters.seamMockBuilders.map(\.label)
			+ parameters.onlyIfAvailableReceivedProperties.map(\.label)
		// Map of (label → (type → disambiguatedLabel)) for flat received
		// parameters whose label collided with another flat parameter. Builder calls
		// for child nodes that would reference the original label must substitute
		// the disambiguated name so the generated code references a real binding.
		// A builder the tree passes up from a call of another module's public mock is read by the leaf that makes the call,
		// wherever it is in the tree, so its parameter is named apart from every label a scope enclosing the leaf declares,
		// which would hide it there.
		let hiddenPassedUpBuilders = Self.hiddenPassedUpBuilders(in: treePropertyNodes)
		let preferredNames = parameters.flatReceivedProperties.map(\.label)
		let namesInScope = Set(otherFlatLabels).union(treeBindingNames)
		// The instance of a `LazilyInstantiated` beside a forwarded property is named after
		// its `LazilyInstantiated`, and is only ever read by the wrapper bound below, so a
		// receive of the forwarded property is not passed it.
		let flatReceivedNames = Self.namesApart(
			preferredNames: preferredNames,
			typeDescriptions: parameters.flatReceivedProperties.map { property in
				parameters.lazilyInstantiatedPropertyByInstanceBesideForwardedProperty[property]?.typeDescription ?? property.typeDescription
			},
			namesInScope: namesInScope,
			reservedNames: namesDeclaredInBuilderFunctions,
			hiddenEntries: Set(parameters.flatReceivedProperties.indices.filter { hiddenPassedUpBuilders.contains(parameters.flatReceivedProperties[$0]) }),
		)
		let onlyIfAvailableOverrides: [OnlyIfAvailableOverride] = if parameters.onlyIfAvailableReceivedProperties.isEmpty {
			[]
		} else {
			Self.onlyIfAvailableOverrides(
				for: parameters.onlyIfAvailableReceivedProperties,
				namedAfter: parameters.lazilyInstantiatedPropertyByInstanceBesideForwardedProperty,
				namesInMockScope: Set(parameters.forwardedDependencies.map(\.property.label))
					.union(parameters.rootDefaultParameters.map(\.label))
					.union(uncoveredDependencyNames)
					.union(treeBindingNames),
				reservedNames: Set(flatReceivedNames).union(namesDeclaredInBuilderFunctions),
			)
		}
		return MockRootParameterNames(
			treeBindingNames: treeBindingNames,
			namesDeclaredInBuilderFunctions: namesDeclaredInBuilderFunctions,
			otherFlatLabels: otherFlatLabels,
			flatReceivedNames: flatReceivedNames,
			onlyIfAvailableOverrides: onlyIfAvailableOverrides,
		)
	}

	/// The arguments of the initializer, or hand-written mock, that the mock of `instantiable` constructs it with which take
	/// a default value and are none of its dependencies, each with its default: `mock()` takes each under its label
	/// (`MockRootParameters.rootDefaultParameters`), which no binding of its tree keeps.
	static func defaultValuedMockParameterArguments(of instantiable: Instantiable) -> [(argument: Initializer.Argument, defaultExpression: String)] {
		let rootConstructionInitializer = instantiable.mockInitializer ?? instantiable.initializer
		let dependencyLabels = Set(instantiable.dependencies.map(\.property.label))
		return (rootConstructionInitializer?.arguments ?? []).compactMap { argument in
			guard !dependencyLabels.contains(argument.innerLabel),
			      !argument.isLeftToItsDefault,
			      let defaultExpression = argument.defaultValueExpression
			else { return nil }
			return (argument, defaultExpression)
		}
	}

	/// How a mock spells each dependency it binds in a form it does not build itself: a promoted dependency
	/// (`DependencyTreeGenerator.createMockRootScopeGenerator`), a flat `mock()` parameter, and an `onlyIfAvailable` override
	/// or parameter (`mockRootParameters`). `==` reads `any P` and `P` as one type, so the properties a mock's tree receives
	/// would hold whichever spelling a walk met first, and a protocol spelled with `any` could lose it in the mock, which
	/// warns in a module that enables the `ExistentialAny` upcoming feature. A dependency the mocked type receives, directly
	/// or through an alias, takes the mocked type's spelling; any other takes the most explicit of its receivers' spellings
	/// in the tree (`ValueSpellings`), which the sets of received properties keep (`insertKeepingMostExplicitSpelling(_:)`).
	///
	/// A deliberate gap, commented where the closure types are built (`MockParameterNode.init`) and where the arguments are
	/// bound (`emitReceiverBindings`): the override closure of a type the mock builds, and the bindings of its arguments in
	/// that type's builder function, take that type's initializer's parameters as they are declared.
	struct MockedTypeSpellings {
		/// - Parameter treeReceivedProperties: The properties the mock's tree receives, each in its receivers' most explicit
		///   spelling.
		init(of instantiable: Instantiable, treeReceivedProperties: some Sequence<Property>) {
			// An alias spells the dependency as its property's type does, where that type is the one `ofType:` names, and never
			// as `ofType:` does: `Service.self` is an expression, which the `ExistentialAny` upcoming feature does not flag.
			// A direct receive decides over an alias, whichever the type declares first; of two of one kind, the first decides.
			var aliasSpelledInstanceProperties = [Property: Property]()
			for dependency in instantiable.dependencies {
				switch dependency.source {
				case .received:
					let instanceProperty = ValueSpellings.instanceProperty(of: dependency.property)
					if spelledInstanceProperties[instanceProperty] == nil {
						spelledInstanceProperties[instanceProperty] = instanceProperty
					}
				case let .aliased(fulfillingProperty, _, _):
					let instanceProperty = ValueSpellings.instanceProperty(of: fulfillingProperty)
					let declaredInstanceProperty = ValueSpellings.instanceProperty(of: Property(label: fulfillingProperty.label, typeDescription: dependency.property.typeDescription))
					if declaredInstanceProperty == instanceProperty, aliasSpelledInstanceProperties[instanceProperty] == nil {
						aliasSpelledInstanceProperties[instanceProperty] = declaredInstanceProperty
					}
				case .instantiated, .forwarded:
					continue
				}
			}
			spelledInstanceProperties.merge(aliasSpelledInstanceProperties) { directlyReceivedProperty, _ in directlyReceivedProperty }
			treeSpellings = ValueSpellings(of: treeReceivedProperties)
		}

		/// `property` with the mock's spelling of the dependency it is a form of: its optional, its unwrapped form, and a
		/// `LazilyInstantiated` or `SendableLazilyInstantiated` of its instance are each a form of one dependency, which the
		/// mock binds once.
		func spelling(of property: Property) -> Property {
			let ownSpelling = spelledInstanceProperties.isEmpty ? nil : spelledInstanceProperties[ValueSpellings.instanceProperty(of: property)]
			return if let ownSpelling {
				ValueSpellings.property(property, spellingInstanceAs: ownSpelling)
			} else {
				treeSpellings.spelling(ofValueOf: property)
			}
		}

		/// `properties`, each spelled as `spelling(of:)` spells it.
		func spellings(of properties: Set<Property>) -> Set<Property> {
			Set(properties.lazy.map(spelling(of:)))
		}

		/// The mocked type's own spelling of the instance of each dependency it receives (`ValueSpellings.instanceProperty(of:)`),
		/// keyed by that instance.
		private var spelledInstanceProperties = [Property: Property]()
		/// The most explicit spelling of each dependency the mock's tree receives.
		private let treeSpellings: ValueSpellings
	}

	/// What a mock root binds at its body's top level, beside the mocked type's own aliases and sites of holes.
	struct MockRootTopLevelNames {
		/// Each `LazilyInstantiated` the mock wraps around an instance it cannot build, unwrapped, once per wrapper type.
		let lazilyInstantiatedPropertiesToBind: [Property]
		/// The name each of `lazilyInstantiatedPropertiesToBind` is bound under, in order.
		let lazilyInstantiatedBindingNames: [String]
		/// The name of the wrapper bound for each received `LazilyInstantiated`, by label and type.
		let lazilyInstantiatedBindingNameMap: [String: [TypeDescription: String]]
		/// The names apart that sibling disambiguation gives the property nodes of the root's level, by label and type.
		let siblingDisambiguationMap: [String: [TypeDescription: String]]
		/// The names the property nodes of the root's level are bound under.
		let treePropertyNodeBindingNames: Set<String>
		/// The names the root's level binds: its property nodes, its `onlyIfAvailable` overrides and its wrappers.
		let rootBindingNames: Set<String>
		/// The names an alias of the mocked type, or a site of one of its holes, is bound apart from (`renamingAliases`):
		/// `rootBindingNames`, and the names of the flat received parameters, which an alias whose label one of them has
		/// would hide from the trees that receive it.
		let namesAliasesAreBoundApartFrom: Set<String>
	}

	/// The names a mock root with `parameters` binds at its body's top level. `generateMockRootCode` binds them, and a public
	/// mock's finding of a site of a hole bound apart reads them (`publicMockHoleSiteBoundApartFinding`), so the two agree on
	/// which sites are bound apart.
	static func mockRootTopLevelNames(of parameters: MockRootParameters, parameterNames: MockRootParameterNames) -> MockRootTopLevelNames {
		// Wrap the instance of each lazily instantiated dependency the mock cannot build, under a name of its
		// own. Types that receive the dependency as `LazilyInstantiated` are passed that name. Rebinding it
		// under the dependency's label where they are built would hide the parameter that holds the instance
		// from the types built there that receive it by value. One wrapper is bound for each wrapper type a
		// label is received as: a receive of `x: LazilyInstantiated<X>?` is passed the binding a receive of
		// `x: LazilyInstantiated<X>` is. Wrappers of one kind around instances of different types under one
		// label are named apart by their instance types, as flat parameters sharing a label are, and so is a
		// wrapper whose name the mock's scope already holds: a parameter, an override, or a binding of the
		// tree, or that a builder function beneath it declares. Renaming the generated binding leaves every
		// label the declarations wrote as it is.
		var lazilyInstantiatedPropertiesToBind = [Property]()
		var lazilyInstantiatedPropertiesSeen = Set<Property>()
		for receivedProperty in parameters.lazilyInstantiatedReceivedProperties
			where lazilyInstantiatedPropertiesSeen.insert(receivedProperty.asUnwrappedProperty).inserted
		{
			lazilyInstantiatedPropertiesToBind.append(receivedProperty.asUnwrappedProperty)
		}
		let onlyIfAvailableOverrides = parameterNames.onlyIfAvailableOverrides
		let lazilyInstantiatedBindingNames = Self.namesApart(
			preferredNames: lazilyInstantiatedPropertiesToBind.map { lazilyInstantiatedProperty in
				"\(lazilyInstantiatedProperty.label)_\(lazilyInstantiatedProperty.propertyType.isSendable ? "sendableLazilyInstantiated" : "lazilyInstantiated")".spelledAsJoinedIdentifier
			},
			typeDescriptions: lazilyInstantiatedPropertiesToBind.map(\.asValidatedForDependencyCycles.typeDescription),
			namesInScope: Set(parameterNames.otherFlatLabels + parameters.flatReceivedProperties.map(\.label))
				.union(parameterNames.flatReceivedNames)
				.union(parameters.flatUncoveredParameters.map(\.label))
				.union(onlyIfAvailableOverrides.map(\.name))
				.union(parameterNames.treeBindingNames)
				.union(parameterNames.namesDeclaredInBuilderFunctions),
			reservedNames: [],
		)
		var lazilyInstantiatedBindingNameByProperty = [Property: String]()
		for (lazilyInstantiatedProperty, bindingName) in zip(lazilyInstantiatedPropertiesToBind, lazilyInstantiatedBindingNames) {
			lazilyInstantiatedBindingNameByProperty[lazilyInstantiatedProperty] = bindingName
		}
		// A wrapper a public mock takes as a parameter is that parameter, which binds nothing apart.
		if !parameters.publicMockWrapperParameterByInstance.isEmpty {
			var parameterNameByInstance = [Property: String]()
			for (property, name) in zip(parameters.flatReceivedProperties, parameterNames.flatReceivedNames) {
				parameterNameByInstance[property] = name
			}
			for override in onlyIfAvailableOverrides {
				parameterNameByInstance[override.receivedProperty] = override.name
			}
			for (instance, wrapper) in parameters.publicMockWrapperParameterByInstance {
				lazilyInstantiatedBindingNameByProperty[wrapper.asUnwrappedProperty] = parameterNameByInstance[instance]
			}
		}
		var lazilyInstantiatedBindingNameMap = [String: [TypeDescription: String]]()
		for receivedProperty in parameters.lazilyInstantiatedReceivedProperties {
			lazilyInstantiatedBindingNameMap[receivedProperty.label, default: [:]][receivedProperty.typeDescription] = lazilyInstantiatedBindingNameByProperty[receivedProperty.asUnwrappedProperty]
		}
		// A call of another module's public mock that takes the wrapper only if available is passed the wrapper a required
		// receive of the label makes the mock bind, as it reads that declaration (`NearestDeclarations.binding(of:)`): the
		// call receives the optional form, which no parameter of this mock stands for.
		for receivedProperty in parameters.lazilyInstantiatedReceivedProperties where !receivedProperty.typeDescription.isOptional {
			let optionalType = TypeDescription.optional(receivedProperty.typeDescription)
			if lazilyInstantiatedBindingNameMap[receivedProperty.label]?[optionalType] == nil {
				lazilyInstantiatedBindingNameMap[receivedProperty.label]?[optionalType] = lazilyInstantiatedBindingNameByProperty[receivedProperty]
			}
		}

		// Sibling-disambig map renames local `let` bindings when the root's own
		// `.instantiated` dep label collides with a promoted sibling — the return
		// call must reference the renamed local.
		let treePropertyNodes = parameters.parameterTree.propertyNodes
		var siblingDisambiguationMap = [String: [TypeDescription: String]]()
		Self.mergeSiblingDisambiguations(into: &siblingDisambiguationMap, for: treePropertyNodes, labelMap: parameters.rootLabelMap)
		// The root's own aliases are bound in the same scope as the dependencies promoted
		// to the root and the `onlyIfAvailable` override bindings. Bind an alias whose label
		// one of those already binds under a name of its own, and pass that name to the root
		// and to the alias's receivers in the tree.
		let treePropertyNodeBindingNames = Set(treePropertyNodes.map { node in
			siblingDisambiguationMap[node.propertyLabel]?[node.typeDescription] ?? node.propertyLabel
		})
		let rootBindingNames = treePropertyNodeBindingNames
			.union(onlyIfAvailableOverrides.map(\.name))
			.union(lazilyInstantiatedBindingNameMap.values.flatMap(\.values))
		return MockRootTopLevelNames(
			lazilyInstantiatedPropertiesToBind: lazilyInstantiatedPropertiesToBind,
			lazilyInstantiatedBindingNames: lazilyInstantiatedBindingNames,
			lazilyInstantiatedBindingNameMap: lazilyInstantiatedBindingNameMap,
			siblingDisambiguationMap: siblingDisambiguationMap,
			treePropertyNodeBindingNames: treePropertyNodeBindingNames,
			rootBindingNames: rootBindingNames,
			// An alias whose label a flat received parameter has would hide that parameter from the dependencies promoted
			// beside it, whose trees receive it: the alias does not provide the receive (`isProvidedByTree`), or the mock
			// would take no parameter for it – an optional alias beside a required non-optional receive, or an alias of
			// another type. That alias is bound under a name of its own too, so that `mock()` keeps its signature.
			namesAliasesAreBoundApartFrom: rootBindingNames.union(parameterNames.flatReceivedNames),
		)
	}

	/// The parameters this scope's `mock()` takes as a mock root. See `MockRootParameters`.
	/// - Parameter mockDefaults: The hand-written mock a flat parameter of each type defaults to.
	func mockRootParameters(instantiable: Instantiable, mockDefaults: [TypeDescription: FlatParameterMockDefault]) async -> MockRootParameters {
		// 1. Build the parameter tree.
		let parameterTree = await rootMockParameterTree
		// A public mock another module generated builds what its call does not pass, so `mock()` takes no parameter or
		// override for what only such calls receive, unless it is itself a public mock, which takes what the calls pass
		// as parameters that default to `nil`, so that its own callers can hand one instance down the chain.
		let receivedOnlyByPublicMockCallsLeftOut = Self.receivedOnlyByPublicMockCallsLeftOut(
			receivedOnlyByPublicMockCalls: receivedOnlyByPublicMockCalls,
			passedByPublicMockCalls: passedByPublicMockCalls,
			mockedType: instantiable,
		)
		// Each in the mocked type's own spelling where it receives the dependency, and otherwise in the most explicit of its
		// receivers' spellings in the tree, which the flat parameters and the `onlyIfAvailable` overrides and parameters declare.
		let receivedProperties = MockedTypeSpellings(of: instantiable, treeReceivedProperties: receivedProperties).spellings(of: receivedProperties.subtracting(receivedOnlyByPublicMockCallsLeftOut))
		let onlyIfAvailableUnwrappedReceivedProperties = receivedOnlyByPublicMockCalls.isEmpty
			? onlyIfAvailableUnwrappedReceivedProperties
			: onlyIfAvailableUnwrappedReceivedProperties.filter { property in
				receivedProperties.contains(property) || receivedProperties.contains(property.asOptionalProperty)
			}

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
		var rootDefaultParameters = [MockRootParameters.RootDefaultParameter]()
		// The parameters of `mock()` that keep their labels, which a binding of the root's tree would hide: the
		// forwarded parameters, which are passed on under their labels, and the default-valued ones, whose labels
		// are those of the construction initializer.
		var parametersKeepingTheirLabels = forwardedDependencies.map(\.property)
		for (argument, defaultExpression) in Self.defaultValuedMockParameterArguments(of: instantiable) {
			// A throwing `@autoclosure` is taken as one that does not throw, since the mock calls it where it builds the type,
			// outside any function that throws; its default throws nothing, or the parameter is left to it.
			let typeDescription = argument.typeDescription.autoclosureTakenWithoutThrowing
			rootDefaultParameters.append(MockRootParameters.RootDefaultParameter(
				label: argument.label,
				typeSource: typeDescription.asFunctionParameter.asSource,
				defaultExpression: defaultExpression,
				typeDescription: typeDescription.strippingEscaping,
			))
			parametersKeepingTheirLabels.append(Property(label: argument.label, typeDescription: argument.typeDescription))
		}
		// A forwarded parameter takes the default the construction gives the parameter of its label, else the hand-written
		// mock its type has.
		var constructionDefaults = [String: String]()
		for argument in rootConstructionInitializer?.arguments ?? [] {
			constructionDefaults[argument.innerLabel] = argument.defaultValueExpression
		}
		var forwardedParameterDefaults = [String: ForwardedParameterDefault]()
		for dependency in forwardedDependencies {
			if let constructionDefault = constructionDefaults[dependency.property.label] {
				forwardedParameterDefaults[dependency.property.label] = .constructionDefault(constructionDefault)
			} else if let mockDefault = mockDefaults[dependency.property.typeDescription] {
				forwardedParameterDefaults[dependency.property.label] = .handWrittenMock(mockDefault)
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

		// A tree node binds a non-optional value, even when it is promoted for a required `x: X?`.
		/// Whether the tree provides a received property, as a scope provides one to the scopes beneath it
		/// (`provides`). A promoted node also provides the non-optional form of its optional property: a
		/// mock builds it, so it binds a non-optional value even when it is promoted for a required `x: X?`.
		/// An `onlyIfAvailable` alias of an optional property binds an optional value, so it does not.
		func isProvidedByTree(_ property: Property) -> Bool {
			Self.provides(property, declaredProperties: propertiesToDeclare, forwardedProperties: [])
				|| (!property.typeDescription.isOptional
					&& treePropertyLabels.contains(property.label)
					&& treePropertyNodes.contains { $0.propertyLabel == property.label && $0.typeDescription == .optional(property.typeDescription) })
		}

		// The lazily instantiated dependencies the tree receives and the mock cannot build. The caller of
		// `mock()` passes the instance of such a dependency, exactly as for one received by value, and the
		// mock wraps it for the types that receive it as `LazilyInstantiated`. A node of another form under
		// the dependency's label, such as an `Instantiator` the mock builds, does not provide it. A node that
		// declares the instance does, though the wrapper cannot be made from it: the node is declared among the
		// tree's bindings, after the wrappers. The mock builds no node for the instance itself beside a received
		// wrapper, which it promotes instead, so that node is a wrapper of the other kind, such as a
		// `SendableLazilyInstantiated<X>` the tree requires beside an `onlyIfAvailable` `LazilyInstantiated<X>?`.
		// An instance the mocked type instantiates and the mock cannot build does provide it, and the wrapper is made
		// from it: `mock()` takes that instance as a parameter, which is in scope before any binding, so the dependency
		// and the wrapper are one instance, as when the mock builds the dependency as the wrapper. The instance of a
		// wrapper the mocked type instantiates and the mock cannot build provides only that wrapper: `mock()` takes the
		// wrapper, which makes no wrapper of the other kind, so the mock takes the instance as well, as it builds a
		// wrapper of the other kind beside a wrapper it builds.
		let mockedTypeUncoveredDependencies = Self.uncoveredInstantiatedDependencies(ofMockedType: instantiable, treePropertyNodes: treePropertyNodes, holeSiteProperties: Set(parameterTree.holeSiteProperties))
		let mockedTypeUncoveredProperties = Set(mockedTypeUncoveredDependencies.map(\.property))
		let mockedTypeUncoveredWrapperInstanceProperties = Set(mockedTypeUncoveredDependencies.compactMap(\.lazilyInstantiatedInstanceProperty))
		/// Whether the tree provides `property` to the receives the caller of `mock()` would otherwise pass it to by
		/// value: the instance a received wrapper is made from, or a received property itself.
		func isProvidedByTreeByValue(_ property: Property) -> Bool {
			isProvidedByTree(property) && !mockedTypeUncoveredWrapperInstanceProperties.contains(property.asUnwrappedProperty)
		}
		let lazilyInstantiatedReceivedProperties = receivedProperties
			.filter {
				$0.typeDescription.lazilyInstantiatedInstanceType != nil
					&& !isProvidedByTree($0)
					&& (!isProvidedByTreeByValue($0.asValidatedForDependencyCycles) || mockedTypeUncoveredProperties.contains($0.asValidatedForDependencyCycles.asUnwrappedProperty))
					&& !isFulfilledByForwardedProperty($0)
			}
			.sorted()
		// The instance of such a dependency can have the label and type of a property the mocked type forwards. The
		// forwarded value comes from outside the tree, so it is not that instance: `mock()` takes the instance as well,
		// under a name of its own, and a receive of the forwarded property is still passed the forwarded value. Each
		// such instance is keyed to the `LazilyInstantiated` it is named after.
		var lazilyInstantiatedPropertyByInstanceBesideForwardedProperty = [Property: Property]()
		for lazilyInstantiatedProperty in lazilyInstantiatedReceivedProperties.reversed()
			where isFulfilledByForwardedProperty(lazilyInstantiatedProperty.asValidatedForDependencyCycles)
		{
			lazilyInstantiatedPropertyByInstanceBesideForwardedProperty[lazilyInstantiatedProperty.asValidatedForDependencyCycles] = lazilyInstantiatedProperty.asUnwrappedProperty
		}
		let lazilyInstantiatedPropertiesBesideForwardedProperties = Set(lazilyInstantiatedPropertyByInstanceBesideForwardedProperty.values)
		// Received properties as the caller of `mock()` provides them: by value.
		let receivedParameterProperties: Set<Property>
		let onlyIfAvailableUnwrappedReceivedParameterProperties: Set<Property>
		if lazilyInstantiatedReceivedProperties.isEmpty {
			receivedParameterProperties = receivedProperties
			onlyIfAvailableUnwrappedReceivedParameterProperties = onlyIfAvailableUnwrappedReceivedProperties
		} else {
			// A `LazilyInstantiated` the mocked type forwards is passed on as it is, so it is not a parameter. The instance
			// of one beside a forwarded property is classified by its own receives, which may require it when every
			// receive of the forwarded property is only if available, or the other way around.
			func isBesideForwardedProperty(_ property: Property) -> Bool {
				lazilyInstantiatedPropertiesBesideForwardedProperties.contains(property.asUnwrappedProperty)
			}
			// A property received by value and the instance of a `LazilyInstantiated` received under its label are one
			// parameter, which `==` reads as one where the two spell a protocol apart, with and without `any`, so the form the
			// mock's order lists first, the one received by value, decides how the parameter is spelled, on every run.
			var receivedParameterPropertiesInMockOrder = Set<Property>()
			for receivedProperty in receivedProperties.sorted(by: { $0.precedesInMockOrder($1) })
				where !isFulfilledByForwardedProperty(receivedProperty) || isBesideForwardedProperty(receivedProperty)
			{
				receivedParameterPropertiesInMockOrder.insert(receivedProperty.asValidatedForDependencyCycles)
			}
			receivedParameterProperties = receivedParameterPropertiesInMockOrder
			// A dependency some receiver requires, as `LazilyInstantiated` or by value, is required.
			onlyIfAvailableUnwrappedReceivedParameterProperties = Set(onlyIfAvailableUnwrappedReceivedProperties.map(\.asValidatedForDependencyCycles))
				.subtracting(
					requiredReceivedProperties.lazy
						.filter { !isFulfilledByForwardedProperty($0) || isBesideForwardedProperty($0) }
						.map(\.asValidatedForDependencyCycles.asUnwrappedProperty),
				)
		}

		let receivedNonOptionalProperties = Set(
			receivedParameterProperties
				.filter { !$0.typeDescription.isOptional },
		)
		var flatReceivedProperties = [Property]()
		var onlyIfAvailableReceivedProperties = [Property]()
		for receivedProperty in receivedParameterProperties.sorted(by: { $0.precedesInMockOrder($1) }) {
			// A forwarded `x: X` fulfills an `x: X?` too, though not the instance of a `LazilyInstantiated` beside it.
			guard lazilyInstantiatedPropertyByInstanceBesideForwardedProperty[receivedProperty] != nil
				|| !forwardedPropertySet.contains(receivedProperty),
				!receivedProperty.typeDescription.isOptional
				|| (
					!receivedNonOptionalProperties.contains(receivedProperty.asUnwrappedProperty)
						&& (lazilyInstantiatedPropertyByInstanceBesideForwardedProperty[receivedProperty] != nil || !forwardedPropertySet.contains(receivedProperty.asUnwrappedProperty))
				)
			else { continue }
			// Optional, defaulting to `nil`, only when every receiver — directly or
			// through an alias, whose fulfilling property is non-optional — receives it
			// `onlyIfAvailable`. A property any receiver requires is a required parameter.
			// A receive of a property the tree provides is handed that node: the mock root's own
			// receive, or an alias's fulfilling property. A tree node with the label and another
			// type does not provide it: the receivers are handed a parameter or an override of
			// their own type, named apart from that node below. Nor does the instance of a wrapper the
			// mocked type instantiates and the mock cannot build provide a wrapper of the other kind.
			guard !isProvidedByTreeByValue(receivedProperty) else { continue }
			if onlyIfAvailableUnwrappedReceivedParameterProperties.contains(receivedProperty.asUnwrappedProperty) {
				onlyIfAvailableReceivedProperties.append(receivedProperty)
			} else {
				flatReceivedProperties.append(receivedProperty)
			}
		}
		// A received dependency the mock cannot build defaults to the hand-written mock its type has, as a forwarded one does.
		var flatReceivedParameterMockDefaults = [Property: FlatParameterMockDefault]()
		for property in flatReceivedProperties {
			flatReceivedParameterMockDefaults[property] = mockDefaults[property.typeDescription]
		}

		var uncoveredDependencies = UncoveredDependencies()
		// Collect uncovered @Instantiated deps from the root type.
		for dependency in mockedTypeUncoveredDependencies {
			// The mocked type is built in the body of `mock()`, outside every builder function.
			uncoveredDependencies.add(dependency, isHiddenWhereReferenced: false, isInstantiatedInSendableFunction: false)
		}
		// Also collect uncovered @Instantiated deps from child types in the tree.
		// When a child has a custom mock method, its @Instantiated deps that aren't
		// in the scope map become builder arguments. These must surface as flat params
		// so the mock body can pass them.
		await Self.collectUncoveredDependenciesFromTree(
			treePropertyNodes,
			namesDeclaredByEnclosingBuilderFunctions: [],
			into: &uncoveredDependencies,
		)

		// Every name the mock root's scope generates – a binding of the tree, a parameter, or an override
		// named apart, a lazily instantiated wrapper, or an alias renamed – is referenced inside the builder
		// functions beneath it, so it is named apart from the names those functions declare, too. A
		// declaration there of a name the root's scope generates would hide the root's binding from the code
		// in that function, which would then read the declaration instead.
		let namesDeclaredInBuilderFunctions = Self.namesDeclaredInBuilderFunctions(of: treePropertyNodes)
		// A promoted dependency whose label a parameter that keeps its label has is named apart from it, since
		// its binding would hide the parameter from the mocked type and from the receivers of the parameter.
		let rootLabelMap = Self.disambiguatePropertyLabels(
			for: treePropertyNodes,
			besideParametersKeepingTheirLabels: parametersKeepingTheirLabels,
			reservedNames: namesDeclaredInBuilderFunctions,
		)
		let treeBindingNames = Self.bindingNames(of: treePropertyNodes, labels: treePropertyLabels, labelMap: rootLabelMap)

		// An uncovered dependency is a `mock()` parameter under its label, unless another uncovered dependency
		// has the label and another type, a forwarded or default-valued parameter has it, a binding of the
		// root's tree has it, the mocked type receives or aliases a dependency under it, which the mock binds
		// under its label, or a builder function around a type that is passed the dependency declares it,
		// which would hide the parameter there. Those are named apart, and each type that is passed one is
		// passed its name. A parameter or override for a dependency only the tree receives under its label is
		// the one renamed, below.
		let uncoveredDependencyNames = Self.namesApart(
			preferredNames: uncoveredDependencies.properties.map(\.label),
			typeDescriptions: uncoveredDependencies.properties.map(\.typeDescription),
			namesInScope: Set(forwardedDependencies.map(\.property.label))
				.union(rootDefaultParameters.map(\.label))
				.union(treeBindingNames)
				.union(instantiable.dependencies.lazy.compactMap { dependency in
					switch dependency.source {
					case .received, .aliased:
						dependency.property.label
					case .instantiated, .forwarded:
						nil
					}
				}),
			reservedNames: namesDeclaredInBuilderFunctions
				.union(flatReceivedProperties.map(\.label))
				.union(onlyIfAvailableReceivedProperties.map(\.label)),
			hiddenEntries: uncoveredDependencies.indicesHiddenWhereReferenced,
		)
		let creatingTypesByProperty = uncoveredDependencies.properties.isEmpty
			? [:]
			: Self.typesCreatingDependencies(
				ofMockedType: instantiable,
				mockedTypeDependencies: mockedTypeUncoveredDependencies,
				treePropertyNodes: treePropertyNodes,
			)
		let uncoveredParameters = uncoveredDependencies.properties.indices.map { index in
			let property = uncoveredDependencies.properties[index]
			let isSendableAutoclosure = uncoveredDependencies.indicesInstantiatedInSendableFunction.contains(index)
			return MockRootParameters.UncoveredParameter(
				property: property,
				label: uncoveredDependencyNames[index],
				// A `@Sendable` autoclosure spells the value it returns, which `@escaping` cannot apply to.
				typeSource: !isSendableAutoclosure && typesDeclaredEscaping.contains(property.typeDescription)
					? property.typeDescription.asFunctionParameter(amongTypesDeclaredEscaping: typesDeclaredEscaping).asSource
					: uncoveredDependencies.typeSources[index],
				instantiatedType: uncoveredDependencies.instantiatedTypes[index],
				isSendableAutoclosure: isSendableAutoclosure,
				creatingTypes: creatingTypesByProperty[property] ?? [],
			)
		}
		// A type that generates its dependency tree takes, in its internal mock, a builder for each hole type and family, in
		// place of its places' parameters and of the builders its calls of other modules' public mocks pass up for it
		// (`SeamMockBuilder`). Every other internal mock takes one for each hole type and family its calls pass up. Every
		// internal mock also takes one for each hole type and family of the places inside the fills of its calls
		// (`FillPlace`), where its twin's fill calls the builder its seam takes.
		//
		// A deliberate gap from the production twin: an internal mock of a type that generates no dependency tree keeps a
		// flat parameter for each type its own tree instantiates that nothing fulfills, outside every fill, as for a seam it
		// builds itself whose hole nothing fills, where the twin takes the seam's builder: flat parameters are its API, and
		// its own tree passes one value per name. Inside a fill it takes a builder, as its twin does. The other site of the
		// gap is `fillPlaces(insideSendableFunction:)`.
		let fillPlaces = instantiable.generateMock != .public ? Self.fillPlaces(in: treePropertyNodes) : (places: [], declaredLabels: [])
		let seamMockBuilders = instantiable.generateMock != .public
			? Self.seamMockBuilders(
				of: instantiable.generatesDependencyTree ? uncoveredParameters : [],
				fillPlaces: fillPlaces.places,
				passedUpBuilders: Self.passedUpBuilders(
					in: treePropertyNodes,
					among: flatReceivedProperties,
					capturedBySendableFunctions: parameterTree.passedUpBuildersCapturedBySendableFunctions,
				),
				otherParameterLabels: Set(forwardedDependencies.map(\.property.label))
					.union(rootDefaultParameters.map(\.label))
					.union(onlyIfAvailableReceivedProperties.map(\.label))
					.union(instantiable.generatesDependencyTree ? [] : uncoveredParameters.map(\.label))
					.union([ReservedName.mockOverridesParameterName]),
				flatReceivedProperties: flatReceivedProperties,
				capturedBySendableFunctions: parameterTree.passedUpBuildersCapturedBySendableFunctions,
				typesDeclaredEscaping: typesDeclaredEscaping,
				treePropertyNodes: treePropertyNodes,
				// The fills' labels name the builders apart only where a fill calls one.
				namesBoundInTheTree: treeBindingNames.union(namesDeclaredInBuilderFunctions).union(fillPlaces.places.isEmpty ? [] : fillPlaces.declaredLabels),
			)
			: []
		let passedUpPropertiesBuiltBySeamMockBuilders = Set(seamMockBuilders.flatMap(\.passedUpProperties))
		flatReceivedProperties.removeAll { passedUpPropertiesBuiltBySeamMockBuilders.contains($0) }
		let builtProperties = Set(seamMockBuilders.flatMap(\.places).map(\.property))
		let flatUncoveredParameters = uncoveredParameters.filter { !builtProperties.contains($0.property) }

		return MockRootParameters(
			parameterTree: parameterTree,
			rootLabelMap: rootLabelMap,
			forwardedDependencies: forwardedDependencies,
			forwardedParameterDefaults: forwardedParameterDefaults,
			rootConstructionInitializer: rootConstructionInitializer,
			rootDefaultParameters: rootDefaultParameters,
			flatReceivedProperties: flatReceivedProperties,
			flatReceivedParameterMockDefaults: flatReceivedParameterMockDefaults,
			onlyIfAvailableReceivedProperties: onlyIfAvailableReceivedProperties,
			flatUncoveredParameters: flatUncoveredParameters,
			seamMockBuilders: seamMockBuilders,
			lazilyInstantiatedReceivedProperties: lazilyInstantiatedReceivedProperties,
			lazilyInstantiatedPropertyByInstanceBesideForwardedProperty: lazilyInstantiatedPropertyByInstanceBesideForwardedProperty,
			publicMockWrapperParameterByInstance: instantiable.generateMock == .public
				? Self.publicMockWrapperParameters(
					replacing: flatReceivedProperties + onlyIfAvailableReceivedProperties,
					lazilyInstantiatedReceivedProperties: lazilyInstantiatedReceivedProperties,
					besideForwardedProperties: lazilyInstantiatedPropertiesBesideForwardedProperties,
					receivedProperties: receivedProperties,
				)
				: [:],
			receivedOnlyByPublicMockCallsLeftOut: receivedOnlyByPublicMockCallsLeftOut,
			typesDeclaredEscaping: typesDeclaredEscaping,
			mockBuilders: mockBuilders,
		)
	}

	/// The wrapper a public mock takes in place of each of `parameters`, the received values it takes, that is the
	/// instance of a `LazilyInstantiated` or `SendableLazilyInstantiated` its tree receives, keyed by the parameter. A
	/// public mock takes such a value as the wrapper, as the type's initializer takes it, optional where the parameter
	/// is, so a caller hands its own wrapper and nothing builds the value before the tree reads it, as in production.
	///
	/// A type of the tree that receives the value by value reads the wrapper's instance where it is built
	/// (`instancesReadThroughPublicMockWrapperParameters(of:mockDefaults:)`), which only a wrapper the mock requires offers.
	///
	/// A deliberate gap from that rule, documented in `public-mock-builders.md`: the mock still takes the instance, and
	/// wraps it, where its tree receives the value in both wrapper kinds, which no one parameter holds; where the mock
	/// names the instance apart beside a forwarded property of its label; and where its tree receives the value only if
	/// available and also by value, since an optional wrapper offers no instance.
	static func publicMockWrapperParameters(
		replacing parameters: [Property],
		lazilyInstantiatedReceivedProperties: [Property],
		besideForwardedProperties: Set<Property>,
		receivedProperties: Set<Property>,
	) -> [Property: Property] {
		guard !lazilyInstantiatedReceivedProperties.isEmpty else { return [:] }
		var wrappersByInstance = [Property: Set<Property>]()
		for wrapper in lazilyInstantiatedReceivedProperties where !besideForwardedProperties.contains(wrapper.asUnwrappedProperty) {
			wrappersByInstance[wrapper.asValidatedForDependencyCycles.asUnwrappedProperty, default: []].insert(wrapper.asUnwrappedProperty)
		}
		var wrapperByParameter = [Property: Property]()
		for parameter in parameters {
			let instance = parameter.asUnwrappedProperty
			guard let wrappers = wrappersByInstance[instance],
			      wrappers.count == 1,
			      let wrapper = wrappers.first
			else { continue }
			if parameter.typeDescription.isOptional {
				guard !receivedProperties.contains(instance), !receivedProperties.contains(instance.asOptionalProperty) else { continue }
				wrapperByParameter[parameter] = wrapper.asOptionalProperty
			} else {
				wrapperByParameter[parameter] = wrapper
			}
		}
		return wrapperByParameter
	}

	/// The values this generator's tree, a public mock's, receives by value whose public mock takes the wrapper its tree
	/// also receives (`publicMockWrapperParameters(…)`): the tree reads each as the wrapper's instance, which
	/// `DependencyTreeGenerator.createMockRootScopeGenerator` builds the tree again to read.
	func instancesReadThroughPublicMockWrapperParameters(of instantiable: Instantiable, mockDefaults: [TypeDescription: FlatParameterMockDefault]) async -> Set<Property> {
		let parameters = await mockRootParameters(instantiable: instantiable, mockDefaults: mockDefaults)
		return Set(parameters.publicMockWrapperParameterByInstance.keys.filter { instance in
			receivedProperties.contains(instance) || receivedProperties.contains(instance.asOptionalProperty)
		})
	}

	/// The places inside the fills of the calls of other modules' public mocks in the tree of `treePropertyNodes`
	/// (`fillPlaces(insideSendableFunction:)`), in the order the calls' nodes are generated, with every label the fills' trees
	/// declare.
	private static func fillPlaces(in treePropertyNodes: [MockParameterNode]) -> (places: [FillPlace], declaredLabels: Set<String>) {
		var places = [FillPlace]()
		var declaredLabels = Set<String>()
		// A stack of its own, since a mock tree can be as deep as the module has types. Only a node that calls a public mock
		// fills a builder (`fillsABuilder`).
		var nodesToVisit = Array(treePropertyNodes.filter(\.subtreeCallsPublicMock).reversed())
		while let node = nodesToVisit.popLast() {
			if let fillingGenerator = node.fillingGenerator {
				let callPlaces = fillingGenerator.fillPlaces(insideSendableFunction: node.requiresSendable)
				places += callPlaces.places.map { place in
					FillPlace(generator: place.generator, dependency: place.dependency, isInsideSendableFunction: place.isInsideSendableFunction, order: places.count + place.order)
				}
				declaredLabels.formUnion(callPlaces.declaredLabels)
			}
			nodesToVisit.append(contentsOf: node.propertyChildren.filter(\.subtreeCallsPublicMock).reversed())
		}
		return (places, declaredLabels)
	}

	/// The builders an internal mock takes: for `uncoveredParameters`, the `@Instantiated` dependencies the tree of a type
	/// that generates its dependency tree cannot build, one per hole type and family, as the type's readable initializer
	/// takes them, and one per hole type and family that the tree's calls of other modules' public mocks pass up, as the
	/// readable initializer of the mock's production tree takes it, in label order. A place built inside a `@Sendable`
	/// function, or held in a `Sendable` wrapper, is the `@Sendable` family's. `mock()` lists them among its flat received
	/// parameters by label. A builder a call of another module's public mock passes up (`passedUpBuilders`) is the mock's
	/// builder of its hole type and family, and no parameter of its own (`passedUpProperties`), in whatever form the call
	/// passes it up, so the mock takes one builder per hole type and family, as its twin does, and a second call never
	/// renames the first's builder. Where the forms differ, the builder takes the type the twin takes (`parameterType(of:)`
	/// below), and a call whose form takes a value the builder does not is handed an adapter (`SeamMockBuilder.adapters`).
	///
	/// A builder is labeled from what it builds alone, as a seam's builder is (`DependencyTreeGenerator.stems(of:)`), with
	/// `_` appended while another parameter of `mock()` has the label (`otherParameterLabels`, and the flat received
	/// properties it is not). The body calls it by its label, unless a name the tree binds at any level has it
	/// (`namesBoundInTheTree`): then by a name of its own apart from every builder function of the tree, which `mock()`
	/// binds first.
	///
	/// The places inside the fills of the tree's calls (`fillPlaces`) join the families of the type's own places, so one
	/// builder serves every place of a hole type and family, and add families of their own.
	/// - Parameter capturedBySendableFunctions: The builders the calls pass up that a `@Sendable` builder function captures,
	///   which `mock()` takes `@Sendable`.
	private static func seamMockBuilders(
		of uncoveredParameters: [MockRootParameters.UncoveredParameter],
		fillPlaces: [FillPlace],
		passedUpBuilders: [Property: MockRootParameters.SeamMockBuilder.PassedUpBuilder],
		otherParameterLabels: Set<String>,
		flatReceivedProperties: [Property],
		capturedBySendableFunctions: Set<Property>,
		typesDeclaredEscaping: Set<TypeDescription>,
		treePropertyNodes: [MockParameterNode],
		namesBoundInTheTree: Set<String>,
	) -> [MockRootParameters.SeamMockBuilder] {
		var placesByFamily = [MockRootParameters.SeamMockBuilder.Family: [MockRootParameters.UncoveredParameter]]()
		var familiesInOrder = [MockRootParameters.SeamMockBuilder.Family]()
		for uncovered in uncoveredParameters {
			let family = MockRootParameters.SeamMockBuilder.Family(
				holeType: SeamSignature.HoleType(instantiatedType: uncovered.instantiatedType.spelledCanonically, builtType: uncovered.property.typeDescription.builtTypeOfWrapper.spelledCanonically),
				isSendable: uncovered.isSendableAutoclosure || uncovered.property.propertyType.isSendable,
			)
			if placesByFamily[family] == nil {
				familiesInOrder.append(family)
			}
			placesByFamily[family, default: []].append(uncovered)
		}
		var fillPlacesByFamily = [MockRootParameters.SeamMockBuilder.Family: [FillPlace]]()
		for fillPlace in fillPlaces {
			let family = MockRootParameters.SeamMockBuilder.Family(of: fillPlace)
			if placesByFamily[family] == nil, fillPlacesByFamily[family] == nil {
				familiesInOrder.append(family)
			}
			fillPlacesByFamily[family, default: []].append(fillPlace)
		}
		// The type a builder the calls pass up is taken as: `@Sendable` where a `@Sendable` builder function captures it, an
		// instantiator's `Builder` through its `Sendable` twin (`TypeDescription.asSendableBuilder`).
		func passedUpType(of property: Property) -> TypeDescription {
			capturedBySendableFunctions.contains(property) && !property.typeDescription.isSendableFunction ? property.typeDescription.asSendableBuilder : property.typeDescription
		}
		// Every builder the calls pass up joins the builder of its family, in the order of the flat received properties, which
		// is a sorted order; a family the mock builds no place of is a builder of its own, after those it builds places of.
		var passedUpPropertiesByFamily = [MockRootParameters.SeamMockBuilder.Family: [Property]]()
		for property in flatReceivedProperties {
			guard let family = passedUpBuilders[property]?.family else { continue }
			if placesByFamily[family] == nil, fillPlacesByFamily[family] == nil, passedUpPropertiesByFamily[family] == nil {
				familiesInOrder.append(family)
			}
			passedUpPropertiesByFamily[family, default: []].append(property)
		}
		guard !familiesInOrder.isEmpty else { return [] }
		var holeTypes = [SeamSignature.HoleType]()
		for family in familiesInOrder where !holeTypes.contains(family.holeType) {
			holeTypes.append(family.holeType)
		}
		let stems = DependencyTreeGenerator.stems(of: holeTypes)
		// The type a family's builder is taken as: where its own places and the calls take it in one type, that type, and
		// where they take it in other forms of a builder that forwards one value – a plain place's builder beside an
		// `Instantiator`'s of a type that conforms to `Instantiable` by hand, which forwards its `ForwardedProperties` – the
		// type the twin takes, the form of its own places and of every place the calls pass up together. Calls whose places
		// forward different values are an error the mock root reports first
		// (`DependencyTreeGenerator.placesForwardingOtherValuesErrors`). A builder taken as a `@Sendable` builder function
		// captures it is of the `@Sendable` family and taken `@Sendable` (`passedUpType(of:)`), so it is one builder with the
		// `@Sendable` builder of its hole type, as an internal mock's own places of a hole type built both directly and inside
		// a `@Sendable` function share one `@Sendable` builder, where a seam's initializer takes a builder of each family.
		func parameterType(of family: MockRootParameters.SeamMockBuilder.Family) -> TypeDescription {
			let ownPlaceProperties = placesByFamily[family, default: []].map(\.property) + fillPlacesByFamily[family, default: []].map(\.dependency.property)
			let propertiesPassedUp = passedUpPropertiesByFamily[family, default: []]
			let agreedType = if ownPlaceProperties.isEmpty, let firstPassedUp = propertiesPassedUp.first {
				passedUpType(of: firstPassedUp).asFunctionParameter(amongTypesDeclaredEscaping: typesDeclaredEscaping)
			} else {
				MockRootParameters.SeamMockBuilder.parameterType(ofPlaceProperties: ownPlaceProperties, in: family)
			}
			guard propertiesPassedUp.contains(where: { passedUpType(of: $0).strippingEscaping.asSource != agreedType.strippingEscaping.asSource }) else { return agreedType }
			return MockRootParameters.SeamMockBuilder.parameterType(
				ofPlaceProperties: ownPlaceProperties + propertiesPassedUp.compactMap { passedUpBuilders[$0] }.flatMap(\.placeProperties),
				in: family,
			)
		}
		let passedUpProperties = Set(passedUpPropertiesByFamily.values.flatMap(\.self))
		var labels = GeneratedNameAllocator(reserving: otherParameterLabels.union(flatReceivedProperties.filter { !passedUpProperties.contains($0) }.map(\.label)))
		var builders = familiesInOrder.map { family in
			let stem = stems[family.holeType, default: ""]
			let label = labels.claim(family.isSendable ? DependencyTreeGenerator.sendableBuilderLabel(ofStem: stem) : DependencyTreeGenerator.plainBuilderLabel(ofStem: stem))
			return MockRootParameters.SeamMockBuilder(label: label, internalName: label, family: family, places: placesByFamily[family, default: []], fillPlaces: fillPlacesByFamily[family, default: []], passedUpProperties: passedUpPropertiesByFamily[family, default: []], parameterType: parameterType(of: family))
		}
		builders.sort { $0.label < $1.label }
		// A builder whose label a name of the tree has is called by a name apart from every builder function of the tree.
		var builderFunctionNames = Set<String>()
		var nodesToVisit = treePropertyNodes
		while let node = nodesToVisit.popLast() {
			builderFunctionNames.insert(functionName(toBuildPropertyNamed: node.propertyLabel))
			nodesToVisit += node.propertyChildren
		}
		var names = GeneratedNameAllocator(reserving: builderFunctionNames.union(namesBoundInTheTree))
		for index in builders.indices where namesBoundInTheTree.contains(builders[index].label) {
			builders[index].internalName = names.claim(functionName(toBuildPropertyNamed: builders[index].label))
		}
		// A call that passes a builder up in a form that takes a value, where the builder takes nothing, is handed an adapter,
		// named apart from the builders, the tree's builder functions and the locals `mock()` binds for its parameters.
		names.reserve(otherParameterLabels.union(flatReceivedProperties.map(\.label)).map { functionName(toBuildPropertyNamed: $0) })
		// Whether a builder of `builderType` takes a value: a wrapper's `Builder`, where a builder that takes nothing is a
		// function type.
		func takesValue(_ builderType: TypeDescription) -> Bool {
			if case .nested = builderType.strippingEscaping {
				true
			} else {
				false
			}
		}
		for index in builders.indices where !takesValue(builders[index].parameterType) {
			for property in builders[index].passedUpProperties where takesValue(passedUpType(of: property)) {
				builders[index].adapters.append(.init(
					property: property,
					name: names.claim(functionName(toBuildPropertyNamed: builders[index].label)),
					typeDescription: passedUpType(of: property).strippingEscaping,
				))
			}
		}
		return builders
	}

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
		// cannot be downcast implicitly. Use what `customMock` returns for those
		// cases, and `typeName` when there is no custom mock.
		let mockMethodReturnType = (instantiable.mockCallReturnType ?? instantiable.concreteInstantiable).asSource

		// A public mock (`generateMock: .public`) is generated by the module that declares the type, which knows the
		// context every public mock of the module shares.
		let publicMock = instantiable.generateMock == .public ? context.publicMockContext : nil

		// 1. Build the parameter tree and identify the flat parameters.
		let parameters = await mockRootParameters(instantiable: instantiable, mockDefaults: context.flatParameterMockDefaults)
		let parameterTree = parameters.parameterTree
		let forwardedDependencies = parameters.forwardedDependencies
		let rootDefaultParameters = parameters.rootDefaultParameters
		let treePropertyNodes = parameterTree.propertyNodes
		let flatReceivedProperties = parameters.flatReceivedProperties
		let flatUncoveredParameters = parameters.flatUncoveredParameters
		// The mocked type declares these for its whole tree: `mock()` takes each as a parameter.
		let mockedTypeUncoveredDependencies = Self.uncoveredInstantiatedDependencies(ofMockedType: instantiable, treePropertyNodes: treePropertyNodes, holeSiteProperties: Set(parameterTree.holeSiteProperties))
		let lazilyInstantiatedPropertyByInstanceBesideForwardedProperty = parameters.lazilyInstantiatedPropertyByInstanceBesideForwardedProperty

		// The names `mockRootParameters` named the uncovered dependencies apart from, which the rest of the mock
		// is named apart from too.
		let parameterNames = Self.mockRootParameterNames(of: parameters)
		let namesDeclaredInBuilderFunctions = parameterNames.namesDeclaredInBuilderFunctions
		let rootLabelMap = parameters.rootLabelMap
		var uncoveredDependencyNameMap = [String: [TypeDescription: String]]()
		// A place a seam's builder builds is bound under the name its parameter would have had.
		for uncoveredParameter in flatUncoveredParameters + parameters.seamMockBuilders.flatMap(\.places) where uncoveredParameter.label != uncoveredParameter.property.label {
			uncoveredDependencyNameMap[uncoveredParameter.property.label, default: [:]][uncoveredParameter.property.typeDescription] = uncoveredParameter.label
		}
		let flatReceivedNames = parameterNames.flatReceivedNames
		var flatParameterDisambiguationMap = [String: [TypeDescription: String]]()
		// A wrapper a public mock takes in place of the instance (`publicMockWrapperParameters(…)`) is no binding of the
		// instance: its receivers are passed it by name (`lazilyInstantiatedBindingNameMap`), and so are the types that read
		// its instance (`dependencyArgument`).
		for (property, name) in zip(flatReceivedProperties, flatReceivedNames)
			where name != property.label
			&& lazilyInstantiatedPropertyByInstanceBesideForwardedProperty[property] == nil
			&& parameters.publicMockWrapperParameterByInstance[property] == nil
		{
			flatParameterDisambiguationMap[property.label, default: [:]][property.typeDescription] = name
		}
		// A call of another module's public mock that passes up a builder is handed the mock's builder of its hole type and
		// family, or the builder's adapter to the form the call passes it up in.
		for builder in parameters.seamMockBuilders {
			let adapterNameByProperty = Dictionary(builder.adapters.map { ($0.property, $0.name) }, uniquingKeysWith: { first, _ in first })
			for property in builder.passedUpProperties {
				let name = adapterNameByProperty[property] ?? builder.internalName
				if property.label != name {
					flatParameterDisambiguationMap[property.label, default: [:]][property.typeDescription] = name
				}
			}
		}
		// safedi-source-rule: allow uniqueKeysWithValues — the keys are the elements of a set, `receivedParameterProperties`.
		let flatReceivedNameByProperty = Dictionary(uniqueKeysWithValues: zip(flatReceivedProperties, flatReceivedNames))
		// No flat received property is a builder the tree passes up: an internal mock takes each through the builder of its hole
		// type and family (`seamMockBuilders`), `@Sendable` where a `@Sendable` builder function captures it, and a public mock,
		// whose leaves receive none, spells its parameters from its plan (`publicMockPlan`) and reads only these labels.
		let flatReceivedParameters = zip(flatReceivedProperties, flatReceivedNames).map { property, name in
			(
				label: name,
				typeSource: property.typeDescription.asFunctionParameter(amongTypesDeclaredEscaping: parameters.typesDeclaredEscaping).asSource,
			)
		}
		let onlyIfAvailableOverrides = parameterNames.onlyIfAvailableOverrides
		let topLevelNames = Self.mockRootTopLevelNames(of: parameters, parameterNames: parameterNames)
		let lazilyInstantiatedPropertiesToBind = topLevelNames.lazilyInstantiatedPropertiesToBind
		let lazilyInstantiatedInstanceProperties = lazilyInstantiatedPropertiesToBind.map(\.asValidatedForDependencyCycles)
		let lazilyInstantiatedBindingNames = topLevelNames.lazilyInstantiatedBindingNames
		var lazilyInstantiatedBindings = [String]()
		// A public mock passes a wrapper it takes as a parameter on as it is (`publicMockWrapperParameters(…)`).
		let wrappersTakenAsParameters = Set(parameters.publicMockWrapperParameterByInstance.values.map(\.asUnwrappedProperty))
		for index in lazilyInstantiatedPropertiesToBind.indices where !wrappersTakenAsParameters.contains(lazilyInstantiatedPropertiesToBind[index]) {
			let lazilyInstantiatedProperty = lazilyInstantiatedPropertiesToBind[index]
			let instanceProperty = lazilyInstantiatedInstanceProperties[index]
			let bindingName = lazilyInstantiatedBindingNames[index]
			let wrapperTypeSource = lazilyInstantiatedProperty.typeDescription.asSource
			// A required receive of an optional `LazilyInstantiated` is handed an optional instance.
			let optionalInstanceProperty = Property(label: instanceProperty.label, typeDescription: .optional(instanceProperty.typeDescription))
			// The parameter may be named apart from its label.
			if let instanceName = flatReceivedNameByProperty[instanceProperty] {
				lazilyInstantiatedBindings.append("\(bodyIndent)let \(bindingName) = \(wrapperTypeSource) { \(instanceName) }")
			} else if mockedTypeUncoveredDependencies.contains(where: { $0.property == instanceProperty }),
			          let uncoveredParameter = flatUncoveredParameters.first(where: { $0.property == instanceProperty })
			{
				// The instance is the parameter of a dependency the mocked type instantiates, which is always passed.
				lazilyInstantiatedBindings.append("\(bodyIndent)let \(bindingName) = \(wrapperTypeSource) { \(uncoveredParameter.label) }")
			} else if let instanceName = flatReceivedNameByProperty[optionalInstanceProperty] {
				lazilyInstantiatedBindings.append("\(bodyIndent)let \(bindingName) = \(instanceName).map { instance in \(wrapperTypeSource) { instance } }")
			} else {
				// The instance is an `onlyIfAvailable` override, which may be named apart from its label.
				let instanceName = onlyIfAvailableOverrides.first { $0.receivedProperty.asUnwrappedProperty == instanceProperty }?.name ?? instanceProperty.label
				lazilyInstantiatedBindings.append("\(bodyIndent)let \(bindingName) = \(instanceName).map { instance in \(wrapperTypeSource) { instance } }")
			}
		}
		let lazilyInstantiatedBindingNameMap = topLevelNames.lazilyInstantiatedBindingNameMap

		// 3. Simple mock case — no tree, no flat parameters.
		// A public mock takes each property received only if available as a parameter, not an override.
		let hasTree = !parameterTree.isEmpty || (publicMock == nil && !onlyIfAvailableOverrides.isEmpty)
		// SafeDIOverrides is only needed when there are property children or
		// onlyIfAvailable entries. Alias-only trees emit `let` bindings directly
		// in the mock body and require no override storage.
		let hasOverridableTree = !treePropertyNodes.isEmpty || (publicMock == nil && !onlyIfAvailableOverrides.isEmpty)
		let hasFlatParameters = !forwardedDependencies.isEmpty
			|| !rootDefaultParameters.isEmpty
			|| !flatReceivedParameters.isEmpty
			|| !flatUncoveredParameters.isEmpty
			|| !parameters.seamMockBuilders.isEmpty
			|| (publicMock != nil && !onlyIfAvailableOverrides.isEmpty)
		let publicMockPlan = publicMock.map { publicMock in
			Self.publicMockPlan(
				of: instantiable,
				parameters: parameters,
				parameterNames: parameterNames,
				context: publicMock,
			)
		}

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
			let code = if let publicMockPlan {
				"""
				extension \(typeName) {
				    \(mockAttributesPrefix)public static func mock() -> \(mockMethodReturnType) {
				        \(construction)
				    }
				}

				\(Self.guardEnumDeclaration(extending: typeName, named: publicMockPlan.guardTypeName))
				"""
			} else {
				"""
				extension \(typeName) {
				    \(mockAttributesPrefix)static func mock() -> \(mockMethodReturnType) {
				        \(construction)
				    }
				}
				"""
			}
			return wrapInConditionalCompilation(code, mockConditionalCompilation: context.mockConditionalCompilation)
		}

		// 4. Build the mock method.
		var lines = [String]()
		lines.append("extension \(typeName) {")

		// Each `public` or `@usableFromInline` declaration of a public mock that names a type SafeDI reads no declaration
		// of is marked for the file's comment.
		let unreadTypeComment = publicMock?.unreadTypeComment
		if let publicMockPlan, !publicMockPlan.providerDeclarations.isEmpty {
			if let marker = unreadTypeComment?.markerLine(namedBy: publicMockPlan.parameters.filter { $0.defaultKind == .provider }.map(\.type), indent: indent) {
				lines.append(marker)
			}
			lines.append(contentsOf: publicMockPlan.providerDeclarations)
			lines.append("")
		}
		if let publicMockPlan, !publicMockPlan.builders.isEmpty {
			// The scope types the builders `mock()` takes are handed, as a seam declares them.
			for declaration in Self.ownScopeTypeDeclarations(
				builders: publicMockPlan.builders,
				scopeEnums: publicMockPlan.scopeEnums,
				holes: publicMockPlan.holes,
				typesDeclaredEscaping: parameters.typesDeclaredEscaping,
				unreadTypeComment: unreadTypeComment,
				namesForwardedTypes: true,
			) {
				lines.append(declaration)
				lines.append("")
			}
		}
		if hasOverridableTree {
			if let publicMock {
				lines.append(Self.publicSafeDIOverridesStruct(
					rootChildren: treePropertyNodes,
					rootLabelMap: rootLabelMap,
					mockedType: instantiable,
					context: publicMock,
					indent: indent,
				))
			} else {
				lines.append(Self.generateSafeDIOverridesStruct(
					rootChildren: treePropertyNodes,
					rootLabelMap: rootLabelMap,
					onlyIfAvailableOverrides: onlyIfAvailableOverrides,
					sendableConfigurationTypeNames: context.sendableConfigurationTypeNames,
					indent: indent,
				))
			}
			lines.append("")
		}

		// Build mock() signature.
		var mockParameters = [String]()
		for dependency in forwardedDependencies {
			let typeSource = dependency.property.typeDescription.asFunctionParameter(amongTypesDeclaredEscaping: parameters.typesDeclaredEscaping).asSource
			switch parameters.forwardedParameterDefaults[dependency.property.label] {
			case let .constructionDefault(defaultExpression):
				mockParameters.append("\(bodyIndent)\(dependency.property.label): \(typeSource) = \(defaultExpression)")
			case let .handWrittenMock(mockDefault):
				mockParameters.append("\(bodyIndent)\(dependency.property.label): \(typeSource) = \(mockDefault.expression)")
			case nil:
				mockParameters.append("\(bodyIndent)\(dependency.property.label): \(typeSource)")
			}
		}
		for rootDefault in rootDefaultParameters {
			mockParameters.append("\(bodyIndent)\(rootDefault.label): \(rootDefault.typeSource) = \(rootDefault.defaultExpression)")
		}
		// A seam's builder is listed among the flat received parameters by label, where an internal mock lists the builders it
		// passes up to another module's public mock, which are received parameters. Their labels are apart.
		var seamMockBuildersToList = parameters.seamMockBuilders[...]
		for (property, flatReceived) in zip(flatReceivedProperties, flatReceivedParameters) {
			while let builder = seamMockBuildersToList.first, builder.label < property.label {
				mockParameters.append("\(bodyIndent)\(builder.label): \(builder.parameterType.asSource)")
				seamMockBuildersToList = seamMockBuildersToList.dropFirst()
			}
			if let mockDefault = parameters.flatReceivedParameterMockDefaults[property] {
				mockParameters.append("\(bodyIndent)\(flatReceived.label): \(flatReceived.typeSource) = \(mockDefault.expression)")
			} else {
				mockParameters.append("\(bodyIndent)\(flatReceived.label): \(flatReceived.typeSource)")
			}
		}
		for builder in seamMockBuildersToList {
			mockParameters.append("\(bodyIndent)\(builder.label): \(builder.parameterType.asSource)")
		}
		for flatUncovered in flatUncoveredParameters {
			if flatUncovered.isSendableAutoclosure {
				mockParameters.append("\(bodyIndent)\(flatUncovered.label): @autoclosure @escaping @Sendable () -> \(flatUncovered.typeSource)")
			} else {
				mockParameters.append("\(bodyIndent)\(flatUncovered.label): \(flatUncovered.typeSource)")
			}
		}
		if hasOverridableTree {
			mockParameters.append("\(bodyIndent)\(ReservedName.mockOverridesParameterName): \(ReservedName.mockOverridesTypeName) = .init()")
		}

		// Each `@Sendable` autoclosure parameter is read into a local before every builder function, under a name
		// no scope rebinds, and the value of one the mocked type itself instantiates is bound under the parameter's
		// name in the body, as a type in the tree binds it in its builder function. The body's binding hides the
		// parameter from the receivers in the tree, which read the value as they did when the parameter was one.
		var sendableAutoclosureParameters = [Property: SendableAutoclosureParameter]()
		var sendableAutoclosureBindings = [String]()
		// A seam's builder is called the same way, by each type that instantiates one of its places, which binds the place
		// under its label, and is first bound under the name the body calls it by where that is not its label.
		for builder in parameters.seamMockBuilders {
			if builder.internalName != builder.label {
				sendableAutoclosureBindings.append("\(bodyIndent)let \(builder.internalName) = \(builder.label)")
			}
			// A call that passes the builder up in a form that takes a value is handed the builder dropping it.
			for adapter in builder.adapters {
				sendableAutoclosureBindings.append("\(bodyIndent)let \(adapter.name): \(adapter.typeDescription.asSource) = { _ in \(builder.internalName)() }")
			}
			for place in builder.places {
				sendableAutoclosureParameters[place.property] = SendableAutoclosureParameter(name: place.label, localName: builder.internalName, valueType: place.property.typeDescription)
			}
		}
		// A place inside a fill is bound the same way, under its label, by the type that instantiates it, in the order the type
		// declares its places (`FillPlace`).
		var fillPlaceBindingsInOrder = [(order: Int, generator: ObjectIdentifier, binding: SendableAutoclosureParameter)]()
		for builder in parameters.seamMockBuilders {
			for place in builder.fillPlaces {
				fillPlaceBindingsInOrder.append((place.order, place.generator, SendableAutoclosureParameter(name: place.dependency.property.label, localName: builder.internalName, valueType: place.dependency.property.typeDescription)))
			}
		}
		var fillPlaceBindingsByGenerator = [ObjectIdentifier: [SendableAutoclosureParameter]]()
		for (_, generator, binding) in fillPlaceBindingsInOrder.sorted(by: { $0.order < $1.order }) {
			fillPlaceBindingsByGenerator[generator, default: []].append(binding)
		}
		let fillPlaceBindings = FillPlaceBindings(bindingsByGenerator: fillPlaceBindingsByGenerator)
		for flatUncovered in flatUncoveredParameters where flatUncovered.isSendableAutoclosure {
			let parameter = SendableAutoclosureParameter(
				name: flatUncovered.label,
				localName: "\(ReservedName.builderFunctionNamePrefix)\(flatUncovered.label)".spelledAsJoinedIdentifier,
			)
			sendableAutoclosureParameters[flatUncovered.property] = parameter
			sendableAutoclosureBindings.append("\(bodyIndent)let \(parameter.localName) = \(parameter.name)")
		}
		for dependency in mockedTypeUncoveredDependencies {
			if let parameter = sendableAutoclosureParameters[dependency.property] {
				sendableAutoclosureBindings.append("\(bodyIndent)\(parameter.binding)")
			}
		}

		// A public mock's tiers are emitted around its body once the body is generated.
		if publicMockPlan == nil {
			lines.append(contentsOf: flatUncoveredParameters.flatMap(\.sharedValueDocumentation).map { "\(indent)\($0)" })
			lines.append("\(indent)\(mockAttributesPrefix)static func mock(")
			lines.append(mockParameters.joined(separator: ",\n"))
			lines.append("\(indent)) -> \(mockMethodReturnType) {")
		}
		let bodyStartIndex = lines.count
		if let publicMockPlan {
			lines.append(contentsOf: publicMockPlan.defaultResolutions)
		}

		// Generate mock body.
		// Sibling-disambig map renames local `let` bindings when the root's own
		// `.instantiated` dep label collides with a promoted sibling — the return
		// call must reference the renamed local.
		var siblingDisambiguationMap = topLevelNames.siblingDisambiguationMap
		// `emitReceiverBindings` also needs the flat-received renames so it can
		// rebind disambiguated flat params back to their natural labels at child
		// scopes. The return call must NOT apply flat-received renames: they
		// target a separate mock parameter, and the root's own `.instantiated`
		// dep must reference its own parameter — not the renamed flat-received.
		// An `onlyIfAvailable` override named apart from its label is rebound to the label
		// by its receivers, as a renamed flat parameter is, at the root and in the tree.
		// The override of the instance of a `LazilyInstantiated` beside a forwarded property is read only by the
		// wrapper bound for it, so a receive of the forwarded property is not passed it.
		var renamedFlatParameterAndOverrideMap = flatParameterDisambiguationMap
		for onlyIfAvailableOverride in onlyIfAvailableOverrides
			where onlyIfAvailableOverride.name != onlyIfAvailableOverride.receivedProperty.label
			&& lazilyInstantiatedPropertyByInstanceBesideForwardedProperty[onlyIfAvailableOverride.receivedProperty] == nil
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
		let treePropertyNodeBindingNames = topLevelNames.treePropertyNodeBindingNames
		let rootBindingNames = topLevelNames.rootBindingNames
		let (rootItems, aliasBindingNames) = Self.renamingAliases(
			in: parameterTree,
			thatRedeclare: topLevelNames.namesAliasesAreBoundApartFrom,
			reservedNames: rootBindingNames
				.union(forwardedDependencies.map(\.property.label))
				.union(rootDefaultParameters.map(\.label))
				.union(flatReceivedParameters.map(\.label))
				.union(flatUncoveredParameters.map(\.label))
				.union(parameterTree.compactMap { item in
					guard case let .alias(alias) = item else { return nil }
					return alias.property.label
				})
				.union(namesDeclaredInBuilderFunctions),
		)
		var treeDisambiguationMap = renamedFlatParameterAndOverrideMap
		for (label, typeMap) in aliasBindingNames {
			for (typeDescription, name) in typeMap {
				treeDisambiguationMap[label, default: [:]][typeDescription] = name
				siblingDisambiguationMap[label, default: [:]][typeDescription] = name
			}
		}
		// The mocked type declares its own uncovered dependencies for its whole tree, so a receive of one there, and an
		// alias of one, is handed the parameter the mocked type is passed. Nothing in the tree receives one from above,
		// so no parameter, override, or wrapper the mock binds for a receiver shares its label and type.
		treeDisambiguationMap = Self.routingReceives(
			of: mockedTypeUncoveredDependencies,
			toParametersNamed: uncoveredDependencyNameMap,
			in: treeDisambiguationMap,
		)
		// The root's own receive of a wrapped lazily instantiated dependency is passed its binding by name too.
		var returnDisambiguationMap = siblingDisambiguationMap
		for (label, typeMap) in lazilyInstantiatedBindingNameMap {
			for (typeDescription, name) in typeMap {
				returnDisambiguationMap[label, default: [:]][typeDescription] = name
			}
		}
		// The root is passed the parameter of each of its own uncovered dependencies by its name.
		for dependency in instantiable.dependencies {
			if case .instantiated = dependency.source,
			   let name = uncoveredDependencyNameMap[dependency.property.label]?[dependency.property.typeDescription]
			{
				returnDisambiguationMap[dependency.property.label, default: [:]][dependency.property.typeDescription] = name
			}
		}

		// A root's own received dependency whose label the root scope already binds – to a node
		// the mock builds for another receiver – cannot be rebound to its label without
		// redeclaring that binding, so the root is passed the dependency's binding by name.
		// So is one whose binding is a node the tree builds under a name of its own: the
		// rebinds precede the tree, so a rebind would reference the node before its declaration.
		var rootDependenciesToRebind = [Dependency]()
		for dependency in instantiable.dependencies {
			if let binding = Self.disambiguatedBinding(
			   	ofReceived: dependency,
			   	unavailableProperties: [],
			   	lazilyInstantiatedInstanceProperties: [],
			   	flatParameterDisambiguationMap: rootDisambiguationMap,
			   ),
			   rootBindingNames.contains(dependency.property.label) || treePropertyNodeBindingNames.contains(binding.name)
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

		// The autoclosure parameters are read first: the tree's builder functions call the locals.
		lines.append(contentsOf: sendableAutoclosureBindings)
		if hasTree {
			// Bind onlyIfAvailable overrides first — tree bindings may reference them. A public mock's are parameters.
			for onlyIfAvailableOverride in onlyIfAvailableOverrides where publicMock == nil {
				lines.append("\(bodyIndent)let \(onlyIfAvailableOverride.name): \(onlyIfAvailableOverride.typeDescription.asSource) = \(ReservedName.mockOverridesParameterName).\(onlyIfAvailableOverride.name)")
			}
			lines.append(contentsOf: lazilyInstantiatedBindings)
			lines.append(contentsOf: rootReceiverBindings)
			// A fill that reads a caller's own value from the root's binding reads it under the name the root binds it under: a
			// parameter, override or alias named apart (`treeDisambiguationMap`), a promoted dependency named apart
			// (`siblingDisambiguationMap`), or the wrapper of a parameter's instance (`lazilyInstantiatedBindingNameMap`).
			var rootBindingNames = treeDisambiguationMap
			for (label, typeMap) in siblingDisambiguationMap {
				rootBindingNames[label, default: [:]].merge(typeMap) { _, siblingName in siblingName }
			}
			for (label, typeMap) in lazilyInstantiatedBindingNameMap {
				rootBindingNames[label, default: [:]].merge(typeMap) { _, wrapperName in wrapperName }
			}
			let fillBindings = FillPlaceBindings(bindingsByGenerator: fillPlaceBindings.bindingsByGenerator, rootBindingNames: rootBindingNames)
			for (fillingGenerator, propertiesGeneratedLater) in rootItems.fillingGenerators {
				try await fillingGenerator.prepareFillCode(propertiesGeneratedLater: propertiesGeneratedLater, fillPlaceBindings: fillBindings)
			}
			let bodyBindings = await Self.generateMockBodyBindings(
				items: rootItems,
				propertyNodeLabelMap: rootLabelMap,
				parentPath: ReservedName.mockOverridesParameterName,
				indent: bodyIndent,
				flatParameterDisambiguationMap: treeDisambiguationMap,
				lazilyInstantiatedBindingNames: lazilyInstantiatedBindingNameMap,
				uncoveredDependencyNames: uncoveredDependencyNameMap,
				sendableAutoclosureParameters: sendableAutoclosureParameters,
				parentConcreteType: nil,
				cycleEdges: context.cycleEdges,
				overridePathReachable: true,
				handWrittenMockDefaultParameters: context.handWrittenMockDefaultParameters,
				sendableConfigurationTypeNames: context.sendableConfigurationTypeNames,
				publicMock: publicMock.map { publicMock in
					PublicMockEmission(
						promotedParameterNames: publicMockPlan?.promotedParameterNames ?? [:],
						context: publicMock,
						sendableConfigurationTypeNames: context.sendableConfigurationTypeNames,
					)
				},
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
		if let publicMockPlan {
			let body = Array(lines[bodyStartIndex...])
			lines.removeSubrange(bodyStartIndex...)
			lines.append(contentsOf: Self.publicMockTiers(
				of: publicMockPlan,
				typeName: typeName,
				returnType: mockMethodReturnType,
				attributesPrefix: mockAttributesPrefix,
				narrowestBody: body,
				unreadTypeComment: unreadTypeComment,
			))
			lines.append("}")
			lines.append("")
			lines.append(contentsOf: Self.guardEnumDeclaration(extending: typeName, named: publicMockPlan.guardTypeName).components(separatedBy: "\n"))
		} else {
			lines.append("\(indent)}")
			lines.append("}")
		}

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
		// Each label names one dependency: `validateDependencyLabelsAreDistinct` rejects a declaration in a generated tree that repeats one.
		let dependenciesByLabel = Dictionary(grouping: instantiable.dependencies, by: \.property.label).compactMapValues(\.first)
		// A mock root that receives a dependency by value is passed the instance of the
		// `LazilyInstantiated` property promoted to its children, when the tree also receives that.
		// So is one that instantiates a dependency the mock builds as the `LazilyInstantiated` its tree receives, and one
		// that receives by value a value its public mock takes as the wrapper its tree receives
		// (`instancesReadThroughPublicMockWrapperParameters(of:mockDefaults:)`), as the rest of its tree reads it.
		let instancePropertiesReadByValue = Set(propertiesToGenerate.compactMap(\.declaredLazilyInstantiatedInstanceProperty))
			.union(lazilyInstantiatedInstanceProperties)
		var parts = [String]()
		for argument in constructionInitializer.arguments {
			if let dependency = dependenciesByLabel[argument.innerLabel] {
				// When the dep's label was sibling-disambiguated in the tree
				// (e.g. root's `service: TypeA` when a promoted sibling is also
				// labeled `service`), the bound `let` uses the disambiguated
				// name. Rewrite the reference so the Root init call finds it.
				let readsInstanceOfLazilyInstantiatedProperty = switch dependency.source {
				case .received, .instantiated:
					instancePropertiesReadByValue.contains(dependency.property.asUnwrappedProperty)
				case .aliased, .forwarded:
					false
				}
				if dependency.source == .received(onlyIfAvailable: true), unavailableOptionalProperties.contains(dependency.property) {
					// Every only-if-available receive no ancestor provides is passed `nil`, as production passes it: those
					// `receivesPassedNil` names (a form the root binds, read by no one) and those nothing above declares.
					parts.append("\(argument.label.spelledAsArgumentLabel): nil")
				} else if readsInstanceOfLazilyInstantiatedProperty {
					let resolved = Self.disambiguatedLazilyInstantiatedBinding(
						named: dependency.property.label,
						withInstanceOfType: dependency.property.typeDescription.unwrapped,
						disambiguationMap: disambiguationMap,
					)?.name ?? argument.innerLabel
					parts.append("\(argument.label.spelledAsArgumentLabel): \(resolved).\(Dependency.lazilyInstantiatedInstancePropertyName)")
				} else {
					let resolved = disambiguationMap[argument.innerLabel]?[dependency.property.typeDescription] ?? argument.innerLabel
					parts.append("\(argument.label.spelledAsArgumentLabel): \(resolved)")
				}
			} else if argument.hasDefaultValue, !argument.isLeftToItsDefault {
				// `mock()` takes an `@autoclosure` parameter as an autoclosure, or a public mock as a closure, and
				// passes its call, so the value is evaluated where the type is built.
				let parameterValue = argument.typeDescription.strippingEscaping.autoclosureValueType == nil ? argument.label : "\(argument.label)()"
				parts.append("\(argument.label.spelledAsArgumentLabel): \(parameterValue)")
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
	///
	/// A dependency whose label is in `bindingNamesPassedByName` is not rebound: its receiver is passed the binding by
	/// name (`receivedBindingNamesPassedByName(to:flatParameterDisambiguationMap:lazilyInstantiatedBindingNames:)`).
	///
	/// A deliberate gap beside `MockedTypeSpellings`, as in `MockParameterNode.init`: each binding is spelled as the
	/// receiving type declares the dependency, so a protocol it spells without `any`, which the mocked type or another
	/// receiver spells with it, warns here in a module that enables the `ExistentialAny` upcoming feature.
	fileprivate static func emitReceiverBindings(
		for dependencies: [Dependency],
		unavailableProperties: Set<Property>,
		lazilyInstantiatedInstanceProperties: Set<Property> = [],
		flatParameterDisambiguationMap: [String: [TypeDescription: String]],
		bindingNamesPassedByName: [String: String] = [:],
		indent: String,
	) -> [String] {
		dependencies.compactMap { dependency in
			guard bindingNamesPassedByName[dependency.property.label] == nil else { return nil }
			return disambiguatedBinding(
				ofReceived: dependency,
				unavailableProperties: unavailableProperties,
				lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties,
				flatParameterDisambiguationMap: flatParameterDisambiguationMap,
			).map {
				"\(indent)let \(dependency.property.label): \($0.typeDescription.asSource) = \($0.name)"
			}
		}
	}

	/// Emits the `let <name> = <localName>()` bindings a scope needs for the `@Sendable` autoclosure
	/// parameters (`parameters`, see `SendableAutoclosureParameter`) of the dependencies of `node` that the
	/// mock cannot build (`uncoveredInstantiatedDependencies(of:)`). Each binding creates the value where the
	/// node is built, once per construction, as production creates the dependency there, and the children
	/// of the node that receive the dependency read the binding (`routingReceives`). A scope that binds one
	/// is a builder function of its own, so that the binding redeclares nothing.
	private static func sendableAutoclosureBindings(
		for node: MockParameterNode,
		parameters: [Property: SendableAutoclosureParameter],
		indent: String,
	) -> [String] {
		guard !parameters.isEmpty else { return [] }
		return uncoveredInstantiatedDependencies(of: node).compactMap { dependency in
			guard let parameter = parameters[dependency.property] else { return nil }
			return "\(indent)\(parameter.binding)"
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

	/// The renamed bindings `node` is passed by name, keyed by the label of the received dependency each fulfills: those
	/// whose label a receive beneath `node` reads by name, from a binding outside the builder function of `node`. A
	/// rebinding of the label inside that function would hide that binding from the receive beneath, which would read the
	/// form `node` receives instead – an `onlyIfAvailable` `user: Draft?` override rebound above a type that receives the
	/// `user: User?` the mock binds as `user`. Production passes each receive the nearest declaration of its label, so the
	/// receive beneath reads the binding it would read if `node` did not receive the label, as the mock root passes its
	/// own renamed receives by name (`generateReturnArgumentList`).
	private static func receivedBindingNamesPassedByName(
		to node: MockParameterNode,
		flatParameterDisambiguationMap: [String: [TypeDescription: String]],
		lazilyInstantiatedBindingNames: [String: [TypeDescription: String]],
	) -> [String: String] {
		guard !flatParameterDisambiguationMap.isEmpty, !node.children.isEmpty else { return [:] }
		var bindingNamesPassedByName = [String: String]()
		for dependency in node.dependencies {
			if let binding = disambiguatedBinding(
				ofReceived: dependency,
				unavailableProperties: node.unavailableProperties,
				lazilyInstantiatedInstanceProperties: node.lazilyInstantiatedInstanceProperties,
				flatParameterDisambiguationMap: flatParameterDisambiguationMap,
			), receiveReadsLabelByName(
				dependency.property.label,
				beneath: node.children,
				flatParameterDisambiguationMap: flatParameterDisambiguationMap,
				lazilyInstantiatedBindingNames: lazilyInstantiatedBindingNames,
			) {
				bindingNamesPassedByName[dependency.property.label] = binding.name
			}
		}
		return bindingNamesPassedByName
	}

	/// Whether a receive among `items`, or beneath them up to a scope that declares `label`, reads `label` by name: a
	/// received dependency or an alias's fulfilling property whose form neither `flatParameterDisambiguationMap` nor
	/// `lazilyInstantiatedBindingNames` renames. A received dependency whose form the first renames is rebound in its
	/// receiver's own builder function, or passed by name, which
	/// `receivedBindingNamesPassedByName(to:flatParameterDisambiguationMap:lazilyInstantiatedBindingNames:)` decides for
	/// that receiver the same way.
	private static func receiveReadsLabelByName(
		_ label: String,
		beneath items: [MockTreeItem],
		flatParameterDisambiguationMap: [String: [TypeDescription: String]],
		lazilyInstantiatedBindingNames: [String: [TypeDescription: String]],
	) -> Bool {
		var readsLabelByName = false
		// A stack of its own, since a mock tree can be as deep as the module has types.
		var itemsToVisit = items
		while !readsLabelByName, let item = itemsToVisit.popLast() {
			switch item {
			case let .alias(alias):
				// As `emitAliasBinding` resolves the fulfilling property.
				readsLabelByName = alias.fulfillingLabel == label
					&& !alias.isBoundToNil
					&& lazilyInstantiatedBindingNames[label]?[alias.fulfillingTypeDescription] == nil
					&& (alias.fulfillingPropertyIsLazilyInstantiatedInstance
						? disambiguatedLazilyInstantiatedBinding(named: label, withInstanceOfType: alias.fulfillingTypeDescription.unwrapped, disambiguationMap: flatParameterDisambiguationMap) == nil
						: flatParameterDisambiguationMap[label]?[alias.fulfillingTypeDescription] == nil)
			case let .property(node):
				// As `dependencyArgument` resolves the argument, beneath the rebinding `emitReceiverBindings` emits.
				readsLabelByName = node.dependencies.contains { dependency in
					dependency.source.isReceived
						&& dependency.property.label == label
						&& !node.unavailableProperties.contains(dependency.property)
						&& lazilyInstantiatedBindingNames[label]?[dependency.property.typeDescription] == nil
						&& disambiguatedBinding(
							ofReceived: dependency,
							unavailableProperties: node.unavailableProperties,
							lazilyInstantiatedInstanceProperties: node.lazilyInstantiatedInstanceProperties,
							flatParameterDisambiguationMap: flatParameterDisambiguationMap,
						) == nil
				}
				// The builder function of a node that instantiates, forwards or renames the label declares it, and what
				// is beneath reads that.
				if !node.dependencies.contains(where: { !$0.source.isReceived && $0.property.label == label }) {
					itemsToVisit.append(contentsOf: node.children)
				}
			}
		}
		return readsLabelByName
	}

	// MARK: MockParameterNode

	/// A node in the mock parameter tree. Each node represents one property edge
	/// in the dependency tree and carries the metadata needed to generate its
	/// `SafeDIMockConfiguration` struct and builder call.
	///
	/// A class, so that the many places mock generation holds a node, in arrays of the tree's items and of its
	/// property nodes, retain one reference rather than copying every field. Every stored property is a `let`, so a
	/// node is a value nothing changes, and `Sendable`.
	final class MockParameterNode: Sendable {
		/// The property label on the parent type's init (e.g., "service", "childBuilder").
		let propertyLabel: String
		/// The position of this node among its siblings in the inline build's order: declaration order, each after the
		/// siblings it depends upon. The mock builds a child that holds one of its places after its siblings that hold
		/// none, but `SafeDIOverrides` and each configuration take their members in this order (`inInlineOrder(_:)`), so
		/// the initializers a person calls follow the order of the same types' internal mock and inline build, and no
		/// change to where the mock builds a child moves them.
		let inlineOrderPosition: Int
		/// The full type description of the property (e.g., `Instantiator<Child>`).
		let typeDescription: TypeDescription
		/// The instantiated type — `typeDescription.asInstantiatedType` (e.g., `Child`).
		/// Used for the builder closure's return type, disambiguation keys, and
		/// cycle detection. Configuration struct nesting uses `concreteType` instead.
		let instantiatedTypeDescription: TypeDescription
		/// `instantiatedTypeDescription` as the property spells it, `any` kept, which code that declares a value of it spells.
		var instantiatedTypeSpelledAsDeclared: TypeDescription {
			typeDescription.asInstantiatedTypeSpelledAsDeclared
		}

		/// Whether this property is an Instantiator/ErasedInstantiator/Sendable variant.
		let isInstantiator: Bool
		/// Whether the concrete type uses extension-based `instantiate(...)` instead of `init(...)`.
		let isExtensionBased: Bool
		/// Whether this property requires erased-to-concrete existential wrapping.
		let erasedToConcreteExistential: Bool
		/// Child items in the dependency tree (instantiated sub-properties and aliased
		/// bindings declared at this scope). Ordered so that an alias always follows
		/// the child that fulfills it — mirrors production's `orderedPropertiesToGenerate`.
		var children: [MockTreeItem] {
			childItems?.items ?? []
		}

		/// Holds `children`, or `nil` when there are none, as at most nodes.
		let childItems: MockTreeItems?
		/// Non-dependency default-valued parameters from this type's init or customMock.
		let defaultParameters: [DefaultParameter]
		/// All arguments from the init or customMock that will be used for construction.
		/// Determines the builder closure signature (positional unlabeled parameters).
		let constructionArguments: [Initializer.Argument]
		/// The isolation the init or customMock spells (`Initializer.spelledIsolation`), which a public mock's
		/// construction function that calls it mirrors.
		let constructionIsolation: String?
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
		/// The type the construction returns: what the user-defined mock method returns (`Instantiable.mockCallReturnType`)
		/// when `useMockInitializer`, else `concreteType`. Unlike `instantiatedTypeDescription`, it does not depend on the
		/// property the node builds, so a public mock's construction function, which every node of the type built this way
		/// shares, returns it (`publicConstructionFunctions`).
		let constructionReturnType: TypeDescription
		/// The custom mock method name (e.g., "customMock"), if any.
		let customMockName: String?
		/// The concrete type (e.g., `ConcreteService`), which may differ from `instantiatedTypeDescription`
		/// when the property uses an existential wrapper (e.g., `AnyService` fulfilled by `ConcreteService`).
		let concreteType: TypeDescription
		/// The file that declares `concreteType`, as `Instantiable.sourceFilePath` records it.
		let sourceFilePath: String?
		/// Where the hand-written mock `useMockInitializer` selects is declared, when the type has one.
		let mockDeclarationLocation: Dependency.DeclarationLocation?
		/// How the node calls the public mock another module generated for its type, which the tree cannot build
		/// itself, or `nil` for a node built as its type's own module would build it.
		let publicMockCall: PublicMockCall?
		/// In a public mock's tree, the payloads of the cases on the routes to the places beneath this node, bound before its
		/// builder function is declared (`SeamHoles.valuesBindings(at:)`), inside the builder function of the node above.
		let valuesBindings: [ValuesBinding]
		/// In a public mock's tree, the member calls of its builder structs at the top of this node's `@Sendable` builder
		/// function, whose results the function could not capture from outside it (`SeamHoles.memberCallsInsideFunction(at:)`).
		let memberCallsInsideBuilderFunction: [ValuesBinding]
		/// For a node that calls another module's public mock and fills some of its builders, the generator of the call,
		/// which holds the fills' code (`ScopeGenerator.fillCode(propertiesGeneratedLater:)`), and what the call passes
		/// each builder it fills, by label.
		let fillingGenerator: ScopeGenerator?
		let holeArgumentValuesByLabel: [String: String]
		/// For a node that calls another module's public mock, what the call itself passes each builder whose places it fills,
		/// by label (`ScopeGenerator.publicMockBuilderStructValuesByLabel`), where an override closure of the node is handed
		/// `holeArgumentValuesByLabel`'s value.
		let publicMockBuilderStructValuesByLabel: [String: String]
		/// For a node that calls another module's public mock that takes no `SafeDIOverrides`, what its override closure is
		/// handed for each builder (`ScopeGenerator.publicMockOverrideBuilders`), or `nil` where the call can hand none.
		let publicMockOverrideBuilders: [String: ScopeGenerator.PublicMockOverrideBuilder]?

		/// Whether the struct that configures this node holds a member for it. A node that calls another module's public mock
		/// that takes no `SafeDIOverrides` offers its closure only where its call can hand the called `mock()` a builder a person
		/// writes for every builder it takes (`ScopeGenerator.publicMockOverrideBuilders`); the struct that holds it, and the
		/// mock's `safeDIOverrides:` parameter, stay where it does not, so adding the closure later breaks no caller.
		///
		/// A deliberate gap, commented where the call is emitted (`generateMockBodyBindings`): see
		/// `ScopeGenerator.publicMockOverrideBuilders`, which also offers none where a call inside the call's fills re-enters
		/// one of its level functions and a fill reads a value of the caller's scope.
		var offersOverrideClosure: Bool {
			guard let publicMockCall, !publicMockCall.takesOverrides else { return true }
			return publicMockOverrideBuilders != nil
		}

		/// The `propertiesGeneratedLater` of the body of this node's builder function, which declares the fills of
		/// `fillingGenerator` beside the node's children: the fills are generated with them, as production generates a
		/// seam call's fills, so a receive inside one of a property generated after the call is passed `nil`. Read only
		/// for a node with a `fillingGenerator`.
		let fillPropertiesGeneratedLater: Set<Property>
		/// The names of the fills of enclosing calls that calls in this node's subtree refer to (see
		/// `ScopeGenerator.referencedFillNamesByKey`), which no builder function declared around them may share.
		let referencedFillNames: Set<String>
		/// Forwarded properties on this type (relevant for Instantiator edges).
		let forwardedProperties: Set<Property>
		/// `ScopeGenerator.typesDeclaredEscaping` of the scope this node builds.
		let typesDeclaredEscaping: Set<TypeDescription>
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
		/// The `closedOnDeclaration` of the scope this node was built from: for a cycle-closing node, the declaration it
		/// repeats, whose builder function it calls or hands to its wrapper.
		let closedOnDeclaration: ScopeGenerator.BuiltDeclaration?
		/// What a node beneath this one repeats to be built again around it, which then reads no override of its own
		/// (`generateMockBodyBindings`' `isCycleNode`): the type it is instantiated as, built for the same concrete type, as
		/// a cycle repeats a declaration (see `ScopeGenerator.closedOnDeclaration`). Two declarations of one type that
		/// `fulfilledByType:` resolves to different types are two nodes, each reading its own override.
		var cycleNodeKey: String {
			"\(instantiatedTypeDescription.asSource) fulfilled by \(concreteType.asSource)"
		}

		/// The `cycleClosedOnDeclarations` of the scope this node was built from.
		let cycleClosedOnDeclarations: Set<ScopeGenerator.BuiltDeclaration>
		/// The `isReferencedByCycleClosingScope` of the scope this node was built from.
		let isReferencedByCycleClosingScope: Bool
		/// The `cycleParameters` of the scope this node was built from: the parameters of the builder function a lazy
		/// cycle closes on that this node declares, or, for a cycle-closing node, that it passes the function it refers to.
		let cycleParameters: [CycleParameter]
		/// Those of `cycleParameters` this node passes `nil`, since they are unavailable where it passes them.
		let cycleParameterArgumentUnavailableProperties: Set<Property>
		/// The received properties in scope only as the instance of a `LazilyInstantiated` property where this node
		/// passes `cycleParameters`.
		let callSiteLazilyInstantiatedInstanceProperties: Set<Property>
		/// The `buildsInSendableFunction` of the scope this node was built from.
		let buildsInSendableFunction: Bool
		/// Whether this node is inside a sendable scope (descendant of SendableInstantiator).
		/// When `true`, the `safeDIBuilder` closure on `SafeDIMockConfiguration` is `@Sendable`.
		let requiresSendable: Bool
		/// For a member of a loop of builders among the children of the scope that holds this node (see
		/// `ReceivedBuilderLoops`), the loop, named by the index of its first member among those children; `nil` for every
		/// other node.
		let loop: Int?
		/// The `reboundProperties` of the scope this node was built from: the members of its loop that its builder function
		/// wraps again, in the order its body first receives them.
		let reboundProperties: [Property]
		/// Whether anything outside this node's loop reads the wrapper its scope binds. A member of a loop on a mock root
		/// that only the members of its loop receive is not read outside it: the mock declares its builder function, which
		/// the loop's wrappers hand, and no binding of its wrapper, which Swift would report unused.
		let isReadOutsideItsLoop: Bool

		init(
			propertyLabel: String,
			inlineOrderPosition: Int,
			typeDescription: TypeDescription,
			instantiatedTypeDescription: TypeDescription,
			isInstantiator: Bool,
			isExtensionBased: Bool,
			erasedToConcreteExistential: Bool,
			childItems: MockTreeItems?,
			defaultParameters: [DefaultParameter],
			constructionArguments: [Initializer.Argument],
			constructionIsolation: String?,
			dependencies: [Dependency],
			lazilyInstantiatedInstanceProperties: Set<Property>,
			unavailableProperties: Set<Property>,
			useMockInitializer: Bool,
			constructionReturnType: TypeDescription,
			customMockName: String?,
			concreteType: TypeDescription,
			sourceFilePath: String?,
			mockDeclarationLocation: Dependency.DeclarationLocation?,
			publicMockCall: PublicMockCall?,
			valuesBindings: [ValuesBinding],
			memberCallsInsideBuilderFunction: [ValuesBinding] = [],
			fillingGenerator: ScopeGenerator?,
			holeArgumentValuesByLabel: [String: String],
			publicMockBuilderStructValuesByLabel: [String: String] = [:],
			publicMockOverrideBuilders: [String: ScopeGenerator.PublicMockOverrideBuilder]? = nil,
			fillPropertiesGeneratedLater: Set<Property>,
			referencedFillNames: Set<String>,
			forwardedProperties: Set<Property>,
			typesDeclaredEscaping: Set<TypeDescription>,
			isPropertyCycle: Bool,
			closedOnDeclaration: ScopeGenerator.BuiltDeclaration?,
			cycleClosedOnDeclarations: Set<ScopeGenerator.BuiltDeclaration>,
			isReferencedByCycleClosingScope: Bool,
			cycleParameters: [CycleParameter],
			cycleParameterArgumentUnavailableProperties: Set<Property>,
			callSiteLazilyInstantiatedInstanceProperties: Set<Property>,
			buildsInSendableFunction: Bool,
			requiresSendable: Bool,
			loop: Int?,
			reboundProperties: [Property],
			isReadOutsideItsLoop: Bool,
		) {
			self.propertyLabel = propertyLabel
			self.inlineOrderPosition = inlineOrderPosition
			self.typeDescription = typeDescription
			self.instantiatedTypeDescription = instantiatedTypeDescription
			self.isInstantiator = isInstantiator
			self.isExtensionBased = isExtensionBased
			self.erasedToConcreteExistential = erasedToConcreteExistential
			self.childItems = childItems
			self.defaultParameters = defaultParameters
			self.constructionArguments = constructionArguments
			self.constructionIsolation = constructionIsolation
			self.dependencies = dependencies
			self.lazilyInstantiatedInstanceProperties = lazilyInstantiatedInstanceProperties
			self.unavailableProperties = unavailableProperties
			self.useMockInitializer = useMockInitializer
			self.constructionReturnType = constructionReturnType
			self.customMockName = customMockName
			self.concreteType = concreteType
			self.sourceFilePath = sourceFilePath
			self.mockDeclarationLocation = mockDeclarationLocation
			self.publicMockCall = publicMockCall
			self.valuesBindings = valuesBindings
			self.memberCallsInsideBuilderFunction = memberCallsInsideBuilderFunction
			self.fillingGenerator = fillingGenerator
			self.holeArgumentValuesByLabel = holeArgumentValuesByLabel
			self.publicMockBuilderStructValuesByLabel = publicMockBuilderStructValuesByLabel
			self.publicMockOverrideBuilders = publicMockOverrideBuilders
			self.fillPropertiesGeneratedLater = fillPropertiesGeneratedLater
			self.referencedFillNames = referencedFillNames
			self.forwardedProperties = forwardedProperties
			self.typesDeclaredEscaping = typesDeclaredEscaping
			self.isPropertyCycle = isPropertyCycle
			self.closedOnDeclaration = closedOnDeclaration
			self.cycleClosedOnDeclarations = cycleClosedOnDeclarations
			self.isReferencedByCycleClosingScope = isReferencedByCycleClosingScope
			self.cycleParameters = cycleParameters
			self.cycleParameterArgumentUnavailableProperties = cycleParameterArgumentUnavailableProperties
			self.callSiteLazilyInstantiatedInstanceProperties = callSiteLazilyInstantiatedInstanceProperties
			self.buildsInSendableFunction = buildsInSendableFunction
			self.requiresSendable = requiresSendable
			self.loop = loop
			self.reboundProperties = reboundProperties
			self.isReadOutsideItsLoop = isReadOutsideItsLoop
			// Generation reads these for every node many times, so they are worked out once here.
			let dependencyInnerLabels = Set(dependencies.map(\.property.label))
			self.dependencyInnerLabels = dependencyInnerLabels
			let callSiteArguments = constructionArguments.filter { argument in
				!Self.isElidedInCallSite(argument, dependencyInnerLabels: dependencyInnerLabels)
			}
			self.callSiteArguments = callSiteArguments
			// The override closure of a call of another module's public mock passes what it is handed on to that `mock()`, so
			// a function spelled as a name, such as an erased instantiator's `Builder`, is handed `@escaping` where the called
			// mock takes it so (`PublicMockCall.typesDeclaredEscaping`).
			let builderTypesDeclaredEscaping = publicMockCall?.typesDeclaredEscaping ?? []
			// A deliberate gap beside `MockedTypeSpellings`, which spells what the mock root binds as the mocked type does, or
			// as the most explicit of the tree's receivers does: the closure takes each argument as the initializer declares
			// it, so a protocol the type spells without `any`, which the mocked type or another receiver spells with it, warns
			// here in a module that enables the `ExistentialAny` upcoming feature. The argument reads whichever declaration of
			// its label is nearest above the node, which a type between the node and the mock root can declare in a spelling of
			// its own, and which the node is not told. The bindings of the arguments in the type's builder function share the
			// gap (`emitReceiverBindings`).
			builderParameterTypes = callSiteArguments.map { argument in
				(argument.typeDescription.strippingEscaping.autoclosureValueType ?? argument.typeDescription).asFunctionParameter(amongTypesDeclaredEscaping: builderTypesDeclaredEscaping)
			}
			needsConfigurationStruct = childItems?.containsPropertyNode == true || !defaultParameters.isEmpty || isPropertyCycle
			subtreeCallsPublicMock = publicMockCall != nil || childItems?.propertyNodes.contains(where: \.subtreeCallsPublicMock) == true
		}

		/// Whether this node or a node beneath it calls another module's public mock (`publicMockCall`). The walks that
		/// look for such calls, which nearly every tree has none of, skip a subtree without one.
		let subtreeCallsPublicMock: Bool

		/// The property this node builds.
		var property: Property {
			Property(label: propertyLabel, typeDescription: typeDescription)
		}

		/// `siblings`, the property nodes of one scope, in the inline build's order (`inlineOrderPosition`), which
		/// `SafeDIOverrides` and each configuration take their members in.
		static func inInlineOrder(_ siblings: [MockParameterNode]) -> [MockParameterNode] {
			siblings.sorted { $0.inlineOrderPosition < $1.inlineOrderPosition }
		}

		/// The property-typed children of this node (filters out alias items).
		/// `SafeDIMockConfiguration`, `SafeDIOverrides`, and disambiguation only
		/// concern properties — aliases are plain `let` bindings emitted inline.
		var propertyChildren: [MockParameterNode] {
			childItems?.propertyNodes ?? []
		}

		/// Whether this node needs a full `SafeDIMockConfiguration` struct or can be
		/// inlined as an optional builder closure on the parent. A node needs a struct
		/// when it has property children (subtree customization), non-dependency
		/// defaults, or is a property cycle (the struct may exist from a non-cycle
		/// instance of the same type).
		let needsConfigurationStruct: Bool

		/// Whether a public mock builds this node with a construction function of its type (`publicConstructionExpression`):
		/// it needs a configuration, and calls no other module's public mock that takes `safeDIOverrides`.
		var isBuiltWithPublicConstructionFunction: Bool {
			needsConfigurationStruct && publicMockCall?.takesOverrides != true
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

		/// The member of the enclosing overrides that configures this node when it calls a public mock that takes
		/// `safeDIOverrides`: the mock's own `SafeDIOverrides`, with no builder, since the mock builds the tree. Inside a
		/// `@Sendable` builder function, where the struct cannot be captured, a `@Sendable` closure that returns it.
		/// `nil` for every other node.
		func publicMockOverridesMember(sendable: Bool) -> (type: String, defaultValue: String)? {
			guard let publicMockCall, publicMockCall.takesOverrides else { return nil }
			let overridesType = "\(concreteType.asSource).\(ReservedName.mockOverridesTypeName)"
			return sendable
				? (type: "(@Sendable () -> \(overridesType))?", defaultValue: "nil")
				: (type: overridesType, defaultValue: ".init()")
		}

		/// The call of the public mock this node calls (see `publicMockCall`), which takes `safeDIOverrides`: the tier's
		/// parameters, and the member that configures the node, or the mock's default beneath a pruned edge, where the
		/// node has none. An erased node wraps the call in its eraser, as `constructionExpression` wraps a construction.
		/// - Parameters:
		///   - overridesIsSendableClosure: Whether the member that configures the node is a `@Sendable` closure
		///     (`publicMockOverridesMember(sendable:)`).
		///   - indent: The indentation of the line the expression starts on.
		func publicMockCallExpression(arguments: [String], overridesExpression: String?, overridesIsSendableClosure: Bool, indent: String) -> String {
			var labeledArguments = zip(callSiteArguments, publicMockCallArguments(arguments, of: callSiteArguments, indent: indent)).map { "\($0.label.spelledAsArgumentLabel): \($1)" }
			if let overridesExpression {
				let overrides = overridesIsSendableClosure ? "\(overridesExpression)?() ?? .init()" : overridesExpression
				labeledArguments.append("\(ReservedName.mockOverridesParameterName): \(overrides)")
			}
			let call = "\(concreteType.asSource).\(publicMockCall?.functionName ?? InstantiableVisitor.mockMethodName)(\(labeledArguments.joined(separator: ", ")))"
			return erasedToConcreteExistential ? "\(concreteExistentialType.asSource)(\(call))" : call
		}

		/// `arguments`, those of `surfacedArguments`, as the call of another module's public mock this node makes passes them:
		/// the builder struct it passes a builder that takes one, where an override closure is handed the closure over the enum.
		/// A value spelled over several lines, each further one indented from a line at `ScopeGenerator.standardIndent`, is
		/// indented from `indent`, the line the call starts on.
		func publicMockCallArguments(_ arguments: [String], of surfacedArguments: [Initializer.Argument], indent: String) -> [String] {
			guard !publicMockBuilderStructValuesByLabel.isEmpty else { return arguments }
			return zip(surfacedArguments, arguments).map { argument, value in
				publicMockBuilderStructValuesByLabel[argument.innerLabel].map { builderStruct in
					builderStruct.replacingOccurrences(of: "\n\(ScopeGenerator.standardIndent)", with: "\n\(indent)")
				} ?? value
			}
		}

		/// Whether this argument is a non-dependency defaulted parameter that the
		/// mock call site elides: a `_`-labeled one, or a throwing `@autoclosure`
		/// whose default throws (`Initializer.Argument.isLeftToItsDefault`). Elided parameters are
		/// filled in by Swift's default-argument thunk in the callee's
		/// declaration context, which preserves `Self`-binding and unqualified
		/// name lookup inside the default expression. Dependency parameters
		/// (even when shaped `_ dep: Dep = …`) are never elided — the override
		/// flow must thread the resolved binding through to the callee.
		/// `validateUnlabeledDefaultShape` on the macro rejects the shapes
		/// where eliding would produce an uncallable signature (non-trailing
		/// `_`-labeled default).
		private static func isElidedInCallSite(_ argument: Initializer.Argument, dependencyInnerLabels: Set<String>) -> Bool {
			argument.isLeftToItsDefault
				&& !dependencyInnerLabels.contains(argument.innerLabel)
		}

		/// The labels of `dependencies`.
		private let dependencyInnerLabels: Set<String>

		/// Construction arguments surfaced at the mock call site, with elided
		/// non-dependency defaults removed (`isElidedInCallSite`).
		let callSiteArguments: [Initializer.Argument]

		/// The builder closure type as a Swift source string (unlabeled parameters).
		/// Uses the property type (not the concrete fulfilling type) so the override
		/// closure matches what the parent init expects. Swift covariant return types
		/// ensure a concrete builder (e.g., `ConcreteService.init`) is assignable to
		/// a closure returning the property type (e.g., `() -> ServiceProtocol`).
		var builderClosureType: String {
			let parameterTypes = builderParameterTypes
				.map(\.asSource)
				.joined(separator: ", ")
			return "(\(parameterTypes)) -> \(instantiatedTypeSpelledAsDeclared.asSource)"
		}

		/// What this node's construction reads from its `SafeDIMockConfiguration` struct. Every node of
		/// a type shares the struct `generateMockCode` generates from the first of them, so a node
		/// whose requirements differ from that node's cannot be built from it. `@Sendable` is left
		/// out: it is decided once for every root (`collectSendableConfigurationTypeNames`).
		var configurationRequirements: ConfigurationRequirements {
			ConfigurationRequirements(
				childProperties: propertyChildren.map(\.property),
				defaultParameters: defaultParameters.map { Property(label: $0.label, typeDescription: $0.typeDescription) },
				builderParameterTypes: builderParameterTypes,
				builderArgumentLabels: callSiteArguments.map(\.innerLabel),
			)
		}

		/// See `configurationRequirements`.
		struct ConfigurationRequirements: Equatable {
			/// The properties the node builds itself, each read from the struct's field of the same label.
			let childProperties: [Property]
			/// The non-dependency default-valued parameters, each read from the struct's field of the same label.
			let defaultParameters: [Property]
			/// The parameter types of the struct's builder closure, which the node calls with its arguments.
			let builderParameterTypes: [TypeDescription]
			/// The labels of the values the node passes the struct's builder closure, in order: two constructions that pass
			/// two values of one type in other orders would hand one builder each value in the other's place.
			let builderArgumentLabels: [String]
		}

		/// The builder closure type using the concrete type for the return.
		/// Used in `SafeDIMockConfiguration` structs which are deduplicated by
		/// concrete type and must have a single consistent builder signature.
		var concreteBuilderClosureType: String {
			let parameterTypes = builderParameterTypes
				.map(\.asSource)
				.joined(separator: ", ")
			return "(\(parameterTypes)) -> \(concreteType.asSource)"
		}

		/// The parameter types of the builder closures that override how this node is built, one per call-site argument:
		/// the argument's type, or the type of the value an `@autoclosure` argument takes, which the mock evaluates before
		/// it calls the builder, as it does before it calls the construction.
		let builderParameterTypes: [TypeDescription]

		/// Call-site arguments with labeled non-dependency defaults also elided,
		/// for the pruned-back-edge / unreachable-override case where Swift's
		/// default-argument thunk must fire in the callee's scope. Elided
		/// defaults preserve correct resolution of `Self.*`, private members,
		/// and file-scoped helpers in the default expression, which would
		/// otherwise resolve in the wrong context if inlined at the caller.
		///
		/// A node built with `init` keeps each default that its type's hand-written mock also declares, with the
		/// same label and type, in `handWrittenMockDefaultParameters`: every other property of the type is
		/// configured with the mock's default (`generateConfigurationStruct`), so this one is passed the default
		/// its `SafeDIMockConfiguration` declares (`resolveBuilderArguments`), which is evaluated in the struct, as
		/// it is for those properties. The mock's default expression is not inlined at the call site: the type's
		/// static members and nested types it may name resolve in the struct, nested in the type's extension, but
		/// not in the mock root's extension.
		func callSiteArgumentsForPrunedOverride(handWrittenMockDefaultParameters: [DefaultParameter]) -> [Initializer.Argument] {
			callSiteArguments.filter { argument in
				dependencyInnerLabels.contains(argument.innerLabel)
					|| !argument.hasDefaultValue
					|| (!useMockInitializer && handWrittenMockDefaultParameters.contains(where: {
						$0.isDefault(forParameterLabeled: argument.label, ofType: argument.typeDescription.strippingEscaping)
					}))
			}
		}

		/// The arguments the call site passes: `callSiteArguments` when the node's override path is reachable,
		/// `callSiteArgumentsForPrunedOverride(handWrittenMockDefaultParameters:)` otherwise.
		func surfacedCallSiteArguments(
			overrideReachable: Bool,
			handWrittenMockDefaultParameters: [DefaultParameter],
		) -> [Initializer.Argument] {
			if overrideReachable {
				callSiteArguments
			} else {
				callSiteArgumentsForPrunedOverride(handWrittenMockDefaultParameters: handWrittenMockDefaultParameters)
			}
		}

		/// Whether the node's construction where no override reaches it reads a default from a `SafeDIMockConfiguration`
		/// it builds afresh, `<Type>.SafeDIMockConfiguration().<label>`: whether one of the arguments it surfaces there is
		/// neither a builder its call of another module's public mock fills nor a dependency, as `resolveBuilderArguments`
		/// decides.
		func readsConfigurationBuiltAfresh(handWrittenMockDefaultParameters: [DefaultParameter]) -> Bool {
			callSiteArgumentsForPrunedOverride(handWrittenMockDefaultParameters: handWrittenMockDefaultParameters).contains { argument in
				holeArgumentValuesByLabel[argument.innerLabel] == nil && !dependencyInnerLabels.contains(argument.innerLabel)
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
				"\(nodePath).\(ReservedName.configurationBuilderPropertyName)"
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
				return ": \(instantiatedTypeSpelledAsDeclared.asSource)"
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
		/// The unwrapped override is bound to `safeDIBuilder`, which shadows no
		/// argument: each argument is `nil`, an override path, an extracted local
		/// beginning with `__safeDI_`, a dependency's label, or a name derived from
		/// one with a suffix, and the `@Instantiable` macro rejects a dependency
		/// labeled `safeDIBuilder` (`ReservedName.configurationBuilderProperty`).
		func constructionExpression(
			overrideExpression: String?,
			arguments: [String],
			overrideReachable: Bool,
			handWrittenMockDefaultParameters: [DefaultParameter],
			indent: String = ScopeGenerator.standardIndent,
		) -> String {
			let defaultCall = defaultBuilderCall(
				arguments: arguments,
				overrideReachable: overrideReachable,
				handWrittenMockDefaultParameters: handWrittenMockDefaultParameters,
				indent: indent,
			)
			let defaultConstruction = if erasedToConcreteExistential {
				"\(concreteExistentialType.asSource)(\(defaultCall))"
			} else {
				defaultCall
			}
			guard let overrideExpression else {
				return defaultConstruction
			}
			let overrideName = ReservedName.configurationBuilderPropertyName
			let overrideCall = "\(overrideName)(\(overrideArguments(arguments, overrideReachable: overrideReachable, handWrittenMockDefaultParameters: handWrittenMockDefaultParameters).joined(separator: ", ")))"
			let overrideConstruction = if erasedToConcreteExistential, needsConfigurationStruct {
				"\(concreteExistentialType.asSource)(\(overrideCall))"
			} else {
				overrideCall
			}
			return "if let \(overrideName) = \(overrideExpression) { \(overrideConstruction) } else { \(defaultConstruction) }"
		}

		/// `arguments`, those of the call site, as this node's override closure is handed them: each builder of a call of another
		/// module's public mock as `publicMockOverrideBuilders` says, which reads the values the call passes the called mock.
		private func overrideArguments(_ arguments: [String], overrideReachable: Bool, handWrittenMockDefaultParameters: [DefaultParameter]) -> [String] {
			guard let publicMockOverrideBuilders, !publicMockOverrideBuilders.isEmpty else { return arguments }
			let surfacedArguments = surfacedCallSiteArguments(
				overrideReachable: overrideReachable,
				handWrittenMockDefaultParameters: handWrittenMockDefaultParameters,
			)
			let argumentByLabel = Dictionary(zip(surfacedArguments.map(\.innerLabel), arguments), uniquingKeysWith: { first, _ in first })
			return zip(surfacedArguments, arguments).map { argument, value in
				publicMockOverrideBuilders[argument.innerLabel]?.expression(argumentByLabel: argumentByLabel) ?? value
			}
		}

		/// A direct call expression using the default builder with labeled arguments.
		/// e.g., `ConcreteService(helper: helper)` or `ConcreteService.instantiate(helper: helper)`.
		/// Non-dependency `_`-labeled defaults are absent from `callSiteArguments`,
		/// so the call omits them and Swift's default-argument thunk fills them
		/// in the callee's declaration context.
		///
		/// Pass `overrideReachable: false` when the call lives on a pruned
		/// back-edge path where `resolveBuilderArguments` returned values for
		/// `callSiteArgumentsForPrunedOverride` rather than `callSiteArguments`,
		/// and the same `handWrittenMockDefaultParameters` it was given.
		/// Zipping against the wrong signature would shift labels for arguments
		/// that follow an elided default (e.g. `init(a: A, b: B = ..., c: C)`
		/// with `b` elided would emit `C`'s value under label `b`).
		private func defaultBuilderCall(
			arguments: [String],
			overrideReachable: Bool,
			handWrittenMockDefaultParameters: [DefaultParameter],
			indent: String,
		) -> String {
			let methodName: String = if let publicMockCall {
				publicMockCall.functionName
			} else if useMockInitializer {
				customMockName ?? InstantiableVisitor.mockMethodName
			} else if isExtensionBased {
				InstantiableVisitor.instantiateMethodName
			} else {
				"init"
			}
			let surfacedArguments = surfacedCallSiteArguments(
				overrideReachable: overrideReachable,
				handWrittenMockDefaultParameters: handWrittenMockDefaultParameters,
			)
			let labeledArguments = zip(surfacedArguments, publicMockCallArguments(arguments, of: surfacedArguments, indent: indent))
				.map { $0.0.label == "_" ? $0.1 : "\($0.0.label.spelledAsArgumentLabel): \($0.1)" }
				.joined(separator: ", ")
			if methodName == "init" {
				return "\(concreteType.asSource)(\(labeledArguments))"
			} else {
				return "\(concreteType.asSource).\(methodName)(\(labeledArguments))"
			}
		}

		/// A payload bound before a node's builder function, inside the builder function of the node above
		/// (`MockParameterNode.valuesBindings`).
		struct ValuesBinding: Sendable {
			let binding: SeamHoles.ValuesBinding
			/// The by-value properties whose fields read the instance of the `LazilyInstantiated` their label names.
			let lazilyInstantiatedInstanceProperties: Set<Property>

			/// The line that binds the payload. A label in `bindingNamesPassedByName`, the bindings the node above is passed
			/// by name (`receivedBindingNamesPassedByName(to:flatParameterDisambiguationMap:lazilyInstantiatedBindingNames:)`),
			/// is read under that name: its builder function does not bind the label again, so the label there names a
			/// farther declaration than the one the node above received, which its level carries.
			/// A field of a wrapper the mock binds apart from its instance's label is read under the name
			/// `lazilyInstantiatedBindingNames` gives it there.
			func line(bindingNamesPassedByName: [String: String], lazilyInstantiatedBindingNames: [String: [TypeDescription: String]]) -> String {
				binding.line(readingInstancesOf: lazilyInstantiatedInstanceProperties, bindingNamesPassedByName: bindingNamesPassedByName, lazilyInstantiatedBindingNames: lazilyInstantiatedBindingNames)
			}
		}

		/// A non-dependency default-valued parameter from an init or customMock.
		struct DefaultParameter: Sendable {
			/// The parameter label (e.g., "theme", "isPro").
			let label: String
			/// The type of the parameter, without `@escaping`.
			let typeDescription: TypeDescription
			/// The type of the value the parameter takes: `typeDescription`, or the type an `@autoclosure` parameter's
			/// closure returns.
			let valueTypeDescription: TypeDescription
			/// The default value expression (e.g., ".light", "false").
			let defaultExpression: String
			/// Whether the value's type is spelled as a closure/function type, which a configuration can mark `@Sendable`.
			let isClosureType: Bool
			/// Whether the parameter is declared `@escaping`, so that its type is a function type even when it is a
			/// typealias, which `isClosureType` cannot see through. An `@escaping @autoclosure` parameter's value is not
			/// such a function, so this is `false` for it.
			let isDeclaredEscaping: Bool
			/// Whether the parameter is an `@autoclosure`: a configuration stores a closure that returns the value, which
			/// the mock calls where it builds the type, so the value is evaluated once per construction, as in production.
			var isAutoclosure: Bool {
				typeDescription.autoclosureValueType != nil
			}

			/// This parameter as a public mock takes it: an `@autoclosure` parameter as a closure that returns the value,
			/// which the construction function defaults to a closure that evaluates the default and calls where it builds
			/// the type, so that a caller in another module can leave it out. Any other parameter is unchanged.
			var publicMockForm: DefaultParameter {
				guard isAutoclosure else { return self }
				let closureType = TypeDescription.closure(arguments: [], isAsync: false, doesThrow: false, returnType: valueTypeDescription)
				return DefaultParameter(
					label: label,
					typeDescription: typeDescription,
					valueTypeDescription: closureType,
					defaultExpression: "{ \(defaultExpression) }",
					isClosureType: true,
					isDeclaredEscaping: false,
				)
			}

			/// Whether this is the default of a parameter with `label` and `typeDescription`. The type check is
			/// load-bearing: a hand-written mock's `count: Double = 0.5` is no default for `init`'s `count: Int`.
			func isDefault(forParameterLabeled label: String, ofType typeDescription: TypeDescription) -> Bool {
				self.label == label && self.typeDescription == typeDescription
			}

			/// The labeled, default-valued parameters of `initializer` that fulfill none of `dependencies`, which a
			/// generated mock offers as overrides.
			static func defaultParameters(of initializer: Initializer, dependencies: [Dependency]) -> [DefaultParameter] {
				let dependencyLabels = Set(dependencies.map(\.property.label))
				return initializer.arguments.compactMap { argument in
					guard !dependencyLabels.contains(argument.innerLabel),
					      !argument.isLeftToItsDefault,
					      let defaultExpression = argument.defaultValueExpression
					else { return nil }
					let typeDescription = argument.typeDescription.strippingEscaping
					if let valueTypeDescription = typeDescription.autoclosureValueType {
						return DefaultParameter(
							label: argument.label,
							typeDescription: typeDescription,
							valueTypeDescription: valueTypeDescription,
							defaultExpression: defaultExpression,
							isClosureType: valueTypeDescription.isClosure,
							isDeclaredEscaping: false,
						)
					} else {
						return DefaultParameter(
							label: argument.label,
							typeDescription: typeDescription,
							valueTypeDescription: typeDescription,
							defaultExpression: defaultExpression,
							isClosureType: typeDescription.isClosure,
							isDeclaredEscaping: argument.typeDescription.isEscaping,
						)
					}
				}
			}
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
		/// Whether the alias is an `onlyIfAvailable` alias whose fulfilling property is unavailable, which is bound to `nil`.
		var isBoundToNil = false
		/// For a site of a hole in a public mock's tree, rather than an alias: the hole, whose builder the site calls
		/// with the values in scope there to bind `property`.
		var holeSite: SeamSignature.Hole?

		/// For a rename its scope declares of a member of a loop of builders among the scope's children, which is a member
		/// of that loop (see `ReceivedBuilderLoops`), the loop, named by the index of its first member among those children;
		/// `nil` for every other alias.
		var loop: Int?
		/// The rename as its scope declares it, by which the members of its loop rebind it: `property`, unless a mock root
		/// binds the rename under a name of its own (`renamingAliases`).
		var declaredProperty: Property?
		/// For a site of a hole, the properties its owner holds only as a `LazilyInstantiated` property's instance, which
		/// the site's payload reads as the owner's receivers do.
		var holeSiteLazilyInstantiatedInstanceProperties = Set<Property>()
	}

	// MARK: OnlyIfAvailableOverride

	/// A property a mock root's tree receives only if available that nothing in the mock provides.
	/// The generated `mock()` reads it from an optional `SafeDIOverrides` field, which defaults to `nil`,
	/// into a binding of the same name, and hands it to the receivers of the property.
	struct OnlyIfAvailableOverride {
		/// The property the tree receives: a `@Received(onlyIfAvailable: true)` property, or the
		/// non-optional fulfilling property of an `onlyIfAvailable` alias.
		let receivedProperty: Property
		/// The type of the field and the binding: `receivedProperty`'s type, made optional.
		let typeDescription: TypeDescription
		/// The name of the field and the binding (see `onlyIfAvailableOverrides(for:namedAfter:namesInMockScope:reservedNames:)`).
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

	/// The children of a `MockParameterNode`. A tree of nodes can be as deep as the module has types, so each
	/// node's children are released after the release of the items that hold the node returns, rather than
	/// within it, which would nest a release for each level of the tree.
	final class MockTreeItems: Sendable {
		init(_ items: [MockTreeItem]) {
			self.items = items
			propertyNodes = items.propertyNodes
		}

		deinit {
			var items = [MockTreeItem]()
			swap(&items, &self.items)
			DeferredRelease.release(consume items)
			var propertyNodes = [MockParameterNode]()
			swap(&propertyNodes, &self.propertyNodes)
			DeferredRelease.release(consume propertyNodes)
		}

		/// Mutated only by `deinit`, which has the only access.
		nonisolated(unsafe) private(set) var items: [MockTreeItem]
		/// The property nodes among `items` (`[MockTreeItem].propertyNodes`), which generation reads for every node many
		/// times. Mutated only by `deinit`, which has the only access.
		nonisolated(unsafe) private(set) var propertyNodes: [MockParameterNode]

		/// Whether any of `items` is a property node.
		var containsPropertyNode: Bool {
			!propertyNodes.isEmpty
		}
	}

	/// A directed edge in the global type-reference graph that, when removed,
	/// breaks a cycle. Computed once globally (one back-edge per strongly-connected
	/// component of size > 1) and applied uniformly when generating every type's
	/// configuration struct.
	struct CycleEdge: Hashable {
		let parent: String
		let child: String
	}

	/// The nodes of the configuration types of a mock root's tree, one per type, in the order `generateMockCode`
	/// generates their structs.
	struct ConfigurationTypes: Sendable {
		/// The nodes of the types the tree builds above every node whose type repeats an ancestor's, in the order this
		/// root reaches them.
		let nodes: [MockParameterNode]
		/// The nodes of the other types the tree's code reads a configuration of beneath a node whose type repeats an
		/// ancestor's, one per type and construction, in the order this root reaches them. `generateMockCode` takes them
		/// after every root's `nodes`, so a type the module's trees also configure elsewhere keeps its struct where it was.
		let nodesBeneathRepeatedAncestors: [MockParameterNode]
	}

	/// Collects the nodes of all unique configuration types in this scope's mock parameter tree,
	/// in the order this root reaches them. `generateMockCode` keeps the first root's node for each
	/// type, in alphabetical root order, and generates its struct once with `generateConfigurationStruct`.
	///
	/// Beneath a node whose type repeats an ancestor's, which a cycle edge prunes, a node of another type is recorded only
	/// where the code generated for it reads its configuration (#720): in a public mock, every node it builds with its
	/// type's construction function, which the type's module-level configuration declares; in any other mock, a node whose
	/// construction reads a default of its type's hand-written mock from a `SafeDIMockConfiguration` it builds afresh
	/// (`MockParameterNode.readsConfigurationBuiltAfresh(handWrittenMockDefaultParameters:)`). `generateMockCode` adds
	/// the configurations their structs nest, so that no struct is generated that nothing reads or names.
	func collectConfigurationTypes(
		isPublicMock: Bool,
		handWrittenMockDefaultParameters: [TypeDescription: [MockParameterNode.DefaultParameter]],
	) async -> ConfigurationTypes {
		let parameterTree = await rootMockParameterTree
		return await Self.collectUniqueConfigurationTypes(from: parameterTree.propertyNodes) { node in
			if isPublicMock {
				node.isBuiltWithPublicConstructionFunction
			} else {
				node.readsConfigurationBuiltAfresh(handWrittenMockDefaultParameters: handWrittenMockDefaultParameters[node.concreteType, default: []])
			}
		}
	}

	/// A node of a mock root's parameter tree, with the type that builds the node's property.
	struct BuiltMockParameterNode: Sendable {
		let node: MockParameterNode
		/// The type whose scope declares the node's property: the mock root for a node at the top of the tree.
		let parent: TypeDescription
		/// The mock root whose tree holds the node.
		let mockRoot: TypeDescription
	}

	/// For each of `concreteTypes`, the first node this mock root's tree builds with the type's hand-written
	/// mock and the first it builds without it, among the nodes that read a `SafeDIMockConfiguration` struct,
	/// in the order this root reaches them. `generateMockCode` compares the two kinds of node across every root,
	/// and generates the type's struct from one that reads it.
	///
	/// A node beneath an edge in `cycleEdges` reads no overrides from its struct: its parent's struct has no field
	/// for that edge, so the generated mock builds the node and its subtree without overrides
	/// (`generateMockBodyBindings`). Such nodes are left out. One built with `init` reads the defaults of a struct
	/// it builds afresh, but only for parameters the hand-written mock also defaults, with the same label and type,
	/// which the struct declares whichever kind of node it is generated from.
	func collectConfigurationNodesByConstruction(
		of concreteTypes: Set<TypeDescription>,
		mockRoot: TypeDescription,
		cycleEdges: Set<CycleEdge>,
	) async -> [BuiltMockParameterNode] {
		let parameterTree = await rootMockParameterTree
		var seen = Set<ConstructedType>()
		var result = [BuiltMockParameterNode]()

		// Each node before its children, depth first, in the order the tree declares them, with a stack of the nodes
		// left to walk, since a mock tree can be as deep as the module has types. A node at the top of the tree is a
		// field of `SafeDIOverrides`, which no cycle edge prunes, so it has no parent here.
		var nodesToWalk: [(node: MockParameterNode, parent: TypeDescription?)] = parameterTree.propertyNodes.reversed().map { (node: $0, parent: nil) }
		while let (node, parent) = nodesToWalk.popLast() {
			let isPrunedByCycleEdge = parent.map { cycleEdges.contains(CycleEdge(parent: $0.asSource, child: node.concreteType.asSource)) } ?? false
			guard !isPrunedByCycleEdge else { continue }
			if node.needsConfigurationStruct,
			   concreteTypes.contains(node.concreteType),
			   seen.insert(ConstructedType(concreteType: node.concreteType, usesMockInitializer: node.useMockInitializer)).inserted
			{
				result.append(BuiltMockParameterNode(node: node, parent: parent ?? mockRoot, mockRoot: mockRoot))
			}
			// The node walked next is the last one on the stack, so the first child goes last.
			nodesToWalk.append(contentsOf: node.propertyChildren.reversed().map { (node: $0, parent: node.concreteType) })
		}
		return result
	}

	/// For each type this public mock root's tree builds with a construction function of the type
	/// (`MockParameterNode.isBuiltWithPublicConstructionFunction`), the first node it builds with the type's hand-written
	/// mock and the first it builds without it, in the order the tree declares them. Unlike
	/// `collectConfigurationNodesByConstruction`, a node beneath an edge in `cycleEdges` counts: it reads no overrides,
	/// but it calls its construction's function all the same. A node that closes a cycle (`isPropertyCycle`) does not:
	/// it calls the builder function of the declaration it repeats, and an ancestor builds that declaration with the
	/// same construction. `generateMockCode` declares one function per construction the module's public mocks build a type with.
	func collectPublicConstructionNodes() async -> [MockParameterNode] {
		let parameterTree = await rootMockParameterTree
		var seen = Set<ConstructedType>()
		var result = [MockParameterNode]()
		// Each node before its children, depth first, with a stack of the nodes left to walk, since a mock tree can be as
		// deep as the module has types. The node walked next is the last one on the stack, so the first child goes last.
		var nodesToWalk = [MockParameterNode](parameterTree.propertyNodes.reversed())
		while let node = nodesToWalk.popLast() {
			if node.isBuiltWithPublicConstructionFunction,
			   !node.isPropertyCycle,
			   seen.insert(ConstructedType(concreteType: node.concreteType, usesMockInitializer: node.useMockInitializer)).inserted
			{
				result.append(node)
			}
			nodesToWalk.append(contentsOf: node.propertyChildren.reversed())
		}
		return result
	}

	/// A concrete type, and whether it is built with its hand-written mock.
	struct ConstructedType: Hashable {
		let concreteType: TypeDescription
		let usesMockInitializer: Bool
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
	///
	/// `handWrittenMockDefaultParameters` are the default-valued parameters of the type's hand-written mock, if it
	/// has one. A field for a parameter of the same label and type takes its default from there, whether `node` is
	/// built with the mock or with `init`, so every property of the type is configured with the defaults the mock
	/// declares, whichever node the struct is generated from.
	static func generateConfigurationStruct(
		for node: MockParameterNode,
		cycleEdges: Set<CycleEdge>,
		sendableConfigurationTypeNames: Set<String>,
		handWrittenMockDefaultParameters: [MockParameterNode.DefaultParameter],
	) -> String {
		generateConfigurationStruct(
			for: node,
			indent: standardIndent,
			cycleEdges: cycleEdges,
			requiresSendable: sendableConfigurationTypeNames.contains(node.concreteType.asSource),
			sendableConfigurationTypeNames: sendableConfigurationTypeNames,
			defaultExpression: { defaultParameter in
				handWrittenMockDefaultParameters.first(where: {
					$0.isDefault(forParameterLabeled: defaultParameter.label, ofType: defaultParameter.typeDescription)
				})?.defaultExpression ?? defaultParameter.defaultExpression
			},
		)
	}

	/// Concrete type names referenced by this scope's mock parameter tree from a
	/// `SendableInstantiator` scope. Aggregated across all roots before generation
	/// so every root emits consistent `@Sendable`-ness for a given type's
	/// `SafeDIMockConfiguration` struct.
	func collectSendableConfigurationTypeNames() async -> Set<String> {
		let parameterTree = await rootMockParameterTree
		var result = Set<String>()
		// A worklist of each node's children rather than recursion, since the tree can be as deep as the module has types.
		var nodeListsToVisit = [parameterTree.propertyNodes]
		while let nodes = nodeListsToVisit.popLast() {
			for node in nodes {
				if node.requiresSendable, node.needsConfigurationStruct {
					result.insert(node.concreteType.asSource)
				}
				nodeListsToVisit.append(node.propertyChildren)
			}
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
		// The loop of builders each child is on, and the members of loops on a mock root that nothing outside their loop
		// reads (see `ReceivedBuilderLoops`). Nearly every scope holds no loop.
		var loopByGenerator = [ObjectIdentifier: Int]()
		var membersReadOnlyInsideTheirLoop = Set<ObjectIdentifier>()
		if !receivedBuilderLoops.loopByChildIndex.isEmpty {
			for (index, loop) in receivedBuilderLoops.loopByChildIndex {
				loopByGenerator[ObjectIdentifier(propertiesToGenerate[index])] = loop
			}
			for index in loopMembersReadOnlyInsideTheirLoop() {
				membersReadOnlyInsideTheirLoop.insert(ObjectIdentifier(propertiesToGenerate[index]))
			}
		}

		// The position of each child in the inline build's order, by its index among `propertiesToGenerate`: the build's
		// order without a child that holds a place starting after its siblings, which is the build's order itself where no
		// child holds one.
		let inlineOrderedIndices = propertiesToGenerate.contains(where: startsAsCarrier) ? computeOrderedPropertyToGenerateIndices(startingCarriersLast: false) : orderedPropertyToGenerateIndices
		var inlineOrderPositionByIndex = [Int](repeating: 0, count: propertiesToGenerate.count)
		for (position, index) in inlineOrderedIndices.enumerated() {
			inlineOrderPositionByIndex[index] = position
		}

		// Roots only appear at the top level, never as children here — so the
		// `.root` case is not part of the reachable pattern space and is omitted.
		for (childIndex, child) in zip(orderedPropertyToGenerateIndices, orderedChildren(propertiesGeneratedLater: propertiesGeneratedLater)) {
			let childGenerator = child.generator
			let childPropertiesGeneratedLater = child.propertiesGeneratedLater
			let childUnavailableProperties = child.unavailableProperties
			if case let .hole(property, erasedToConcreteExistential, site?) = childGenerator.scopeData {
				// A site of a hole binds its property from the public mock's builder, as an alias binds its own.
				items.append(.alias(MockAliasNode(
					property: property,
					erasedToConcreteExistential: erasedToConcreteExistential,
					onlyIfAvailable: false,
					fulfillingLabel: site.builderLabel,
					fulfillingTypeDescription: site.builtType,
					fulfillingPropertyIsLazilyInstantiatedInstance: false,
					declarationReference: nil,
					holeSite: site,
					holeSiteLazilyInstantiatedInstanceProperties: childGenerator.callSiteLazilyInstantiatedInstanceProperties,
				)))
			} else if case let .alias(property, fulfillingProperty, erasedToConcreteExistential, onlyIfAvailable, declarationReference) = childGenerator.scopeData {
				items.append(.alias(MockAliasNode(
					property: property,
					erasedToConcreteExistential: erasedToConcreteExistential,
					onlyIfAvailable: onlyIfAvailable,
					fulfillingLabel: fulfillingProperty.label,
					fulfillingTypeDescription: fulfillingProperty.typeDescription,
					fulfillingPropertyIsLazilyInstantiatedInstance: childGenerator.fulfillingPropertyIsLazilyInstantiatedInstance,
					declarationReference: declarationReference,
					// An alias whose fulfilling property is unavailable is declared `nil`, as production declares it.
					isBoundToNil: Self.aliasIsBoundToNil(onlyIfAvailable: onlyIfAvailable, fulfillingProperty: fulfillingProperty, unavailableProperties: childUnavailableProperties),
					loop: loopByGenerator[ObjectIdentifier(childGenerator)],
				)))
			} else if case let .property(childInstantiable, childProperty, _, erasedToConcreteExistential, isPropertyCycle, _) = childGenerator.scopeData {
				let isInstantiator = !childProperty.propertyType.isConstant
				let childInsideSendable = insideSendableScope || childGenerator.buildsInSendableFunction

				// Recurse into children to build the subtree. The child's builder function's own parameters hide the
				// declarations of their labels inside it.
				let childBodyPropertiesGeneratedLater = childGenerator.bodyPropertiesGeneratedLater(childPropertiesGeneratedLater)
				let childItems = await childGenerator.collectMockParameterTree(
					insideSendableScope: childInsideSendable,
					propertiesGeneratedLater: childBodyPropertiesGeneratedLater,
				)
				let childConstructionUnavailableProperties = childGenerator.bodyUnavailableProperties(childUnavailableProperties)

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
					defaultParameters = MockParameterNode.DefaultParameter.defaultParameters(
						of: constructionInitializer,
						dependencies: childInstantiable.dependencies,
					)
				}

				// Collect forwarded properties for Instantiator edges.
				let forwardedProperties = Set(
					childInstantiable.dependencies
						.filter { $0.source == .forwarded }
						.map(\.property),
				)

				items.append(.property(MockParameterNode(
					propertyLabel: childProperty.label,
					inlineOrderPosition: inlineOrderPositionByIndex[childIndex],
					typeDescription: childProperty.typeDescription,
					instantiatedTypeDescription: childProperty.typeDescription.asInstantiatedType,
					isInstantiator: isInstantiator,
					isExtensionBased: childInstantiable.declarationType.isExtension,
					erasedToConcreteExistential: erasedToConcreteExistential,
					childItems: childItems.isEmpty ? nil : MockTreeItems(childItems),
					defaultParameters: defaultParameters,
					constructionArguments: constructionArguments,
					constructionIsolation: constructionInitializer?.spelledIsolation,
					dependencies: childInstantiable.dependencies,
					lazilyInstantiatedInstanceProperties: childGenerator.lazilyInstantiatedInstanceProperties,
					unavailableProperties: childConstructionUnavailableProperties,
					useMockInitializer: useMockInitializer,
					constructionReturnType: (useMockInitializer ? childInstantiable.mockCallReturnType : nil) ?? childInstantiable.concreteInstantiable,
					customMockName: childInstantiable.customMockName,
					concreteType: childInstantiable.concreteInstantiable,
					sourceFilePath: childInstantiable.sourceFilePath,
					mockDeclarationLocation: childInstantiable.mockDeclarationLocation,
					publicMockCall: childGenerator.publicMockCall,
					valuesBindings: childGenerator.valuesBindingsBeforeBuilderFunction,
					memberCallsInsideBuilderFunction: childGenerator.memberCallsInsideBuilderFunction,
					fillingGenerator: childGenerator.fillsABuilder ? childGenerator : nil,
					holeArgumentValuesByLabel: childGenerator.holeArgumentValuesByLabel,
					publicMockBuilderStructValuesByLabel: childGenerator.publicMockBuilderStructValuesByLabel,
					publicMockOverrideBuilders: childGenerator.publicMockOverrideBuilders,
					fillPropertiesGeneratedLater: childBodyPropertiesGeneratedLater,
					referencedFillNames: Set(childGenerator.referencedFillNamesByKey.values),
					forwardedProperties: forwardedProperties,
					typesDeclaredEscaping: childGenerator.typesDeclaredEscaping,
					isPropertyCycle: isPropertyCycle,
					closedOnDeclaration: childGenerator.closedOnDeclaration,
					cycleClosedOnDeclarations: childGenerator.cycleClosedOnDeclarations,
					isReferencedByCycleClosingScope: childGenerator.isReferencedByCycleClosingScope,
					cycleParameters: childGenerator.cycleParameters,
					cycleParameterArgumentUnavailableProperties: Set(childGenerator.cycleParameters.map(\.property)).intersection(childUnavailableProperties),
					callSiteLazilyInstantiatedInstanceProperties: childGenerator.callSiteLazilyInstantiatedInstanceProperties,
					buildsInSendableFunction: childGenerator.buildsInSendableFunction,
					requiresSendable: childInsideSendable,
					loop: loopByGenerator[ObjectIdentifier(childGenerator)],
					reboundProperties: childGenerator.reboundProperties,
					isReadOutsideItsLoop: !membersReadOnlyInsideTheirLoop.contains(ObjectIdentifier(childGenerator)),
				)))
			}
		}

		return items
	}

	/// The `@Instantiated` dependencies of a mock's types that the mock cannot build, which `mock()` takes as
	/// parameters, one for each label and type, in the order they are found.
	private struct UncoveredDependencies {
		private(set) var properties = [Property]()
		/// The type each parameter is spelled with.
		private(set) var typeSources = [String]()
		/// The type each dependency instantiates, which no `@Instantiable` declaration fulfills.
		private(set) var instantiatedTypes = [TypeDescription]()
		/// The indices of the dependencies whose label a builder function around a type passed them declares.
		private(set) var indicesHiddenWhereReferenced = Set<Int>()
		/// The indices of the dependencies that a type built inside a `@Sendable` builder function instantiates
		/// (`MockRootParameters.UncoveredParameter.isSendableAutoclosure`).
		private(set) var indicesInstantiatedInSendableFunction = Set<Int>()

		mutating func add(_ dependency: Dependency, isHiddenWhereReferenced: Bool, isInstantiatedInSendableFunction: Bool) {
			let property = dependency.property
			let index: Int
			if let existingIndex = properties.firstIndex(of: property) {
				index = existingIndex
			} else {
				index = properties.count
				properties.append(property)
				// Route through `asFunctionParameter` so closure types surface
				// as `@escaping` — matching the `rootDefaultParameters` and
				// flat-received emission conventions. Idempotent for non-closures.
				typeSources.append(property.propertyType.isConstant
					? property.typeDescription.asInstantiatedTypeSpelledAsDeclared.asFunctionParameter.asSource
					: property.typeDescription.asFunctionParameter.asSource)
				instantiatedTypes.append(dependency.asInstantiatedType)
			}
			if isHiddenWhereReferenced {
				indicesHiddenWhereReferenced.insert(index)
			}
			if isInstantiatedInSendableFunction {
				indicesInstantiatedInSendableFunction.insert(index)
			}
		}
	}

	/// Walks the parameter tree and collects `@Instantiated` dependencies from child
	/// types that aren't fulfilled by their own child nodes. These are deps that
	/// surface through builder arguments (especially via custom mock methods) but aren't
	/// fulfilled by any type in the scope map. `async` for the reason `generateMockBodyBindings` is.
	///
	/// A type is passed such a dependency where it is built, inside the builder functions of the nodes
	/// above it. `namesDeclaredByEnclosingBuilderFunctions` holds the names those functions declare –
	/// their parameters and the bindings of their dependencies, other than the dependencies they are
	/// passed themselves – which hide a parameter of the same name there.
	private static func collectUncoveredDependenciesFromTree(
		_ nodes: [MockParameterNode],
		namesDeclaredByEnclosingBuilderFunctions: Set<String>,
		into uncoveredDependencies: inout UncoveredDependencies,
	) async {
		for node in nodes {
			let propertyChildren = node.propertyChildren
			var uncoveredLabels = Set<String>()
			for dependency in uncoveredInstantiatedDependencies(of: node) {
				uncoveredLabels.insert(dependency.property.label)
				uncoveredDependencies.add(
					dependency,
					isHiddenWhereReferenced: namesDeclaredByEnclosingBuilderFunctions.contains(dependency.property.label),
					// The node is built inside a `@Sendable` builder function: its own, or one around it.
					isInstantiatedInSendableFunction: node.requiresSendable,
				)
			}
			// Skip recursion into property cycle children — they're self-references
			// whose deps would incorrectly surface as uncovered.
			let nonCycleChildren = propertyChildren.filter { !$0.isPropertyCycle }
			guard !nonCycleChildren.isEmpty else { continue }
			var namesDeclaredByChildrensEnclosingBuilderFunctions = namesDeclaredByEnclosingBuilderFunctions
			for dependency in node.dependencies where !uncoveredLabels.contains(dependency.property.label) {
				namesDeclaredByChildrensEnclosingBuilderFunctions.insert(dependency.property.label)
			}
			await collectUncoveredDependenciesFromTree(
				nonCycleChildren,
				namesDeclaredByEnclosingBuilderFunctions: namesDeclaredByChildrensEnclosingBuilderFunctions,
				into: &uncoveredDependencies,
			)
		}
	}

	/// The `@Instantiated` dependencies of `node`'s type that the mock cannot build, which `mock()` takes as
	/// parameters: those no property child of the node builds.
	private static func uncoveredInstantiatedDependencies(of node: MockParameterNode) -> [Dependency] {
		// Nearly every node builds every dependency it instantiates.
		var childLabels: Set<String>?
		return node.dependencies.filter { dependency in
			switch dependency.source {
			case .instantiated:
				if childLabels == nil {
					childLabels = Set(node.propertyChildren.map(\.propertyLabel)).union(node.children.holeSiteProperties.map(\.label))
				}
				return childLabels?.contains(dependency.property.label) == false
			case .received, .aliased, .forwarded:
				return false
			}
		}
	}

	/// The `@Instantiated` dependencies of the mocked type, `instantiable`, that the mock cannot build, which
	/// `mock()` takes as parameters: those no node of the mock root's tree, `treePropertyNodes`, builds. A node
	/// promoted to the root under a dependency's label, of another type, does not build it. The `LazilyInstantiated`
	/// the mock builds the dependency as, when the tree receives that, does.
	private static func uncoveredInstantiatedDependencies(
		ofMockedType instantiable: Instantiable,
		treePropertyNodes: [MockParameterNode],
		holeSiteProperties: Set<Property>,
	) -> [Dependency] {
		// The properties the tree's nodes build, each also as the instance of a `LazilyInstantiated` it builds, collected
		// once rather than for each dependency.
		var builtProperties: Set<Property>?
		return instantiable.dependencies.filter { dependency in
			switch dependency.source {
			case .instantiated:
				guard !holeSiteProperties.contains(dependency.property) else { return false }
				if builtProperties == nil {
					var properties = Set<Property>()
					for node in treePropertyNodes {
						let property = node.property
						properties.insert(property)
						if let instanceProperty = property.asLazilyInstantiatedInstanceProperty {
							properties.insert(instanceProperty)
						}
					}
					builtProperties = properties
				}
				return builtProperties?.contains(dependency.property) == false
			case .received, .aliased, .forwarded:
				return false
			}
		}
	}

	/// The types that create each dependency the mock cannot build, each type once however many places in the tree build
	/// it: the mocked type, then the types of its tree depth first, each type's children in the order it declares them
	/// rather than the order they are built in, followed at the mock root by the dependencies the mock promotes. The tree
	/// is walked with a stack, since it can be as deep as the module has types.
	private static func typesCreatingDependencies(
		ofMockedType instantiable: Instantiable,
		mockedTypeDependencies: [Dependency],
		treePropertyNodes: [MockParameterNode],
	) -> [Property: [TypeDescription]] {
		var typesByProperty = [Property: [TypeDescription]]()
		for dependency in mockedTypeDependencies {
			typesByProperty[dependency.property, default: []].append(instantiable.concreteInstantiable)
		}
		var nodesToVisit = Array(inDeclarationOrder(treePropertyNodes, declaredBy: instantiable.dependencies).reversed())
		while let node = nodesToVisit.popLast() {
			for dependency in uncoveredInstantiatedDependencies(of: node)
				where typesByProperty[dependency.property]?.contains(node.concreteType) != true
			{
				typesByProperty[dependency.property, default: []].append(node.concreteType)
			}
			// As `collectUncoveredDependenciesFromTree` does, whose parameters these are.
			let nonCycleChildren = node.propertyChildren.filter { !$0.isPropertyCycle }
			nodesToVisit.append(contentsOf: inDeclarationOrder(nonCycleChildren, declaredBy: node.dependencies).reversed())
		}
		return typesByProperty
	}

	/// `nodes`, the children of a type that declares `dependencies`, in the order it declares them; any it does not
	/// declare, which the mock promotes to its root, stay in their order after those.
	private static func inDeclarationOrder(_ nodes: [MockParameterNode], declaredBy dependencies: [Dependency]) -> [MockParameterNode] {
		var declarationIndexByLabel = [String: Int]()
		for (index, dependency) in dependencies.enumerated() where declarationIndexByLabel[dependency.property.label] == nil {
			declarationIndexByLabel[dependency.property.label] = index
		}
		return nodes.indices
			.sorted { (declarationIndexByLabel[nodes[$0].propertyLabel] ?? dependencies.count, $0) < (declarationIndexByLabel[nodes[$1].propertyLabel] ?? dependencies.count, $1) }
			.map { nodes[$0] }
	}

	/// `disambiguationMap` for the scopes built where the type that instantiates `uncoveredDependencies`, which the
	/// mock cannot build, has declared them: inside the type's builder function, or throughout the tree of the mocked
	/// type. As in production, where a receiver is handed the property the closest type above it declares, a receive
	/// of one of them there is handed the `mock()` parameter the type is passed, not a renamed parameter or override of
	/// the same label and type that an enclosing scope binds. A parameter that keeps its label is in scope there, as
	/// the type's declaration would be. One that `uncoveredDependencyNames` names apart from its label is rebound under
	/// the label by each receiver, as a renamed flat parameter is.
	private static func routingReceives(
		of uncoveredDependencies: [Dependency],
		toParametersNamed uncoveredDependencyNames: [String: [TypeDescription: String]],
		in disambiguationMap: [String: [TypeDescription: String]],
	) -> [String: [TypeDescription: String]] {
		guard !uncoveredDependencies.isEmpty else { return disambiguationMap }
		var disambiguationMap = removingRenames(
			hiddenByDeclarationsOf: [],
			parameters: uncoveredDependencies.map(\.property),
			from: disambiguationMap,
		)
		for dependency in uncoveredDependencies {
			if let parameterName = uncoveredDependencyNames[dependency.property.label]?[dependency.property.typeDescription] {
				disambiguationMap[dependency.property.label, default: [:]][dependency.property.typeDescription] = parameterName
			}
		}
		return disambiguationMap
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
		labelMap: [String: [TypeDescription: String]],
	) {
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
	/// and each needs its own name. A disambiguated label is never one of `reservedNames`.
	/// - Parameter parametersKeepingTheirLabels: The parameters of the function whose body binds `nodes` that
	///   keep their labels, which a node's binding would hide: a mock root's `@Forwarded` and default-valued
	///   parameters. A node that shares a label with one is named apart from it, as from a sibling: a mocked
	///   type that forwards `x: X` while a dependency it receives requires `x: Instantiator<X>` gets the entry
	///   `x_Instantiator__X`.
	/// Returns a dictionary mapping each node's label and property type to its disambiguated label.
	static func disambiguatePropertyLabels(
		for nodes: [MockParameterNode],
		besideParametersKeepingTheirLabels parametersKeepingTheirLabels: [Property] = [],
		reservedNames: Set<String> = [],
	) -> [String: [TypeDescription: String]] {
		let labels = nodes.map(\.propertyLabel)
		let parameterLabels = Set(parametersKeepingTheirLabels.map(\.label))
		let collidingLabels = collidingLabels(in: labels).union(parameterLabels.intersection(labels))
		let collidingNodes = nodes.filter { collidingLabels.contains($0.propertyLabel) }
		let collidingNames = identifierSafeNames(
			for: collidingNodes.map {
				(
					label: $0.propertyLabel,
					suffixTypes: [$0.instantiatedTypeDescription.simplified, $0.instantiatedTypeDescription, $0.typeDescription],
				)
			},
			besideEntriesKeepingTheirNames: parametersKeepingTheirLabels.compactMap { parameter in
				guard collidingLabels.contains(parameter.label) else { return nil }
				let instantiatedTypeDescription = parameter.typeDescription.asInstantiatedType
				return (
					label: parameter.label,
					suffixTypes: [instantiatedTypeDescription.simplified, instantiatedTypeDescription, parameter.typeDescription],
				)
			},
			// Labels that don't need disambiguation stay as they are, and so do the parameters' labels.
			reservedNames: Set(labels).subtracting(collidingLabels).union(parameterLabels).union(reservedNames),
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
	/// each node's label, disambiguated as `labelMap`, from `disambiguatePropertyLabels`, names it when
	/// siblings or a parameter that keeps its label share it.
	private static func bindingNames(
		of nodes: [MockParameterNode],
		labels: Set<String>,
		labelMap: [String: [TypeDescription: String]],
	) -> Set<String> {
		// Most scopes have no two children with one label and no parameter with a child's label, which leaves
		// every label as it is.
		guard labels.count < nodes.count
			|| labelMap.contains(where: { label, namesByTypeDescription in namesByTypeDescription.values.contains { $0 != label } })
		else { return labels }
		return Set(nodes.map { disambiguatedLabel(for: $0, labelMap: labelMap) })
	}

	/// The builders an internal mock's tree `nodes` passes up from its calls of other modules' public mocks, which the mock
	/// takes as parameters (see `PublicMockCall.passedUpBuilders`), whose label a scope beneath the mock root's level that
	/// encloses a leaf reading one declares, which would hide the parameter from that leaf.
	private static func hiddenPassedUpBuilders(in nodes: [MockParameterNode]) -> Set<Property> {
		var hidden = Set<Property>()
		// A stack of the nodes left to visit, each with the labels the builder functions enclosing it declare, since a mock
		// tree can be as deep as the module has types. A subtree that calls no public mock passes nothing up.
		var nodesToVisit = nodes.filter(\.subtreeCallsPublicMock).map { (node: $0, labelsDeclaredAbove: Set<String>()) }
		while let (node, labelsDeclaredAbove) = nodesToVisit.popLast() {
			var labelsDeclared = labelsDeclaredAbove
			for dependency in node.dependencies {
				switch dependency.source {
				case .received:
					if let publicMockCall = node.publicMockCall, publicMockCall.passesUpBuilder(receivedAs: dependency.property) {
						if labelsDeclaredAbove.contains(dependency.property.label) {
							hidden.insert(dependency.property)
						}
					}
				case .instantiated, .forwarded, .aliased:
					labelsDeclared.insert(dependency.property.label)
				}
			}
			nodesToVisit.append(contentsOf: node.propertyChildren.filter(\.subtreeCallsPublicMock).map { (node: $0, labelsDeclaredAbove: labelsDeclared) })
		}
		return hidden
	}

	/// Each builder among `flatReceivedProperties` that the tree `nodes` passes up from a call of another module's public
	/// mock (`PublicMockCall.passedParameters`), with its family – the called builder's hole type, and the `@Sendable`
	/// family where the called builder is one or a `@Sendable` builder function captures it (`capturedBySendableFunctions`)
	/// – and the called builders it stands for.
	private static func passedUpBuilders(
		in nodes: [MockParameterNode],
		among flatReceivedProperties: [Property],
		capturedBySendableFunctions: Set<Property>,
	) -> [Property: MockRootParameters.SeamMockBuilder.PassedUpBuilder] {
		// The leaf declares the builder as it is passed, which a flat received property spells without `@escaping`.
		func key(of property: Property) -> String {
			"\(property.label): \(property.typeDescription.strippingEscaping.asSource)"
		}
		var candidateByKey = [String: Property]()
		for property in flatReceivedProperties {
			candidateByKey[key(of: property)] = property
		}
		var passedUpBuilderByProperty = [Property: MockRootParameters.SeamMockBuilder.PassedUpBuilder]()
		var nodesToVisit = nodes.filter(\.subtreeCallsPublicMock)
		while let node = nodesToVisit.popLast() {
			if let publicMockCall = node.publicMockCall {
				for parameter in publicMockCall.passedParameters {
					guard let builder = parameter.builder, let property = candidateByKey[key(of: parameter.dependency.property)] else { continue }
					let family = MockRootParameters.SeamMockBuilder.Family(
						holeType: builder.enumKey.holeType,
						isSendable: builder.enumKey.isSendable || capturedBySendableFunctions.contains(property),
					)
					passedUpBuilderByProperty[property, default: .init(family: family)].calledBuilders.append((builder, publicMockCall.calledBuilders))
				}
			}
			nodesToVisit.append(contentsOf: node.propertyChildren.filter(\.subtreeCallsPublicMock))
		}
		return passedUpBuilderByProperty
	}

	/// The names the builder functions beneath a mock root's scope may declare: the labels of the
	/// dependencies of each node of the tree whose root-level property nodes are `nodes` – the parameters of
	/// its builder function, the receivers rebound in it, and the bindings of the properties it instantiates
	/// and aliases.
	private static func namesDeclaredInBuilderFunctions(of nodes: [MockParameterNode]) -> Set<String> {
		var names = Set<String>()
		// A stack of the nodes left to visit, since a mock tree can be as deep as the module has types.
		var nodesToVisit = nodes
		while let node = nodesToVisit.popLast() {
			for dependency in node.dependencies {
				names.insert(dependency.property.label)
			}
			nodesToVisit.append(contentsOf: node.propertyChildren)
		}
		return names
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
	/// - Parameter lazilyInstantiatedPropertyByInstance: The `LazilyInstantiated` a property is the instance of, when
	///   the override is named after it rather than after its own type.
	private static func onlyIfAvailableOverrides(
		for receivedProperties: [Property],
		namedAfter lazilyInstantiatedPropertyByInstance: [Property: Property],
		namesInMockScope: Set<String>,
		reservedNames: Set<String>,
	) -> [OnlyIfAvailableOverride] {
		let typeDescriptions = receivedProperties.map { property in
			property.typeDescription.isOptional ? property.typeDescription : .optional(property.typeDescription)
		}
		let names = namesApart(
			preferredNames: receivedProperties.map(\.label),
			typeDescriptions: receivedProperties.indices.map { index in
				lazilyInstantiatedPropertyByInstance[receivedProperties[index]].map { .optional($0.typeDescription) } ?? typeDescriptions[index]
			},
			namesInScope: namesInMockScope,
			reservedNames: reservedNames,
		)
		return receivedProperties.indices.map { index in
			OnlyIfAvailableOverride(
				receivedProperty: receivedProperties[index],
				typeDescription: typeDescriptions[index],
				name: names[index],
			)
		}
	}

	/// The names of entries bound in one scope, in the order of `preferredNames`: each entry's preferred name,
	/// unless another entry prefers it too, it is one of `namesInScope`, or the entry is in `hiddenEntries`, whose
	/// preferred name a declaration hides where the entry is referenced. Those entries are named apart by
	/// `identifierSafeNames`: by the preferred name followed by the entry's type in `typeDescriptions`, never
	/// taking a name in `namesInScope`, in `reservedNames`, or that another entry prefers or is named by.
	private static func namesApart(
		preferredNames: [String],
		typeDescriptions: [TypeDescription],
		namesInScope: Set<String>,
		reservedNames: Set<String>,
		hiddenEntries: Set<Int> = [],
	) -> [String] {
		let collidingNames = collidingLabels(in: preferredNames).union(namesInScope.intersection(preferredNames))
		guard !collidingNames.isEmpty || !hiddenEntries.isEmpty else { return preferredNames }
		let collidingIndices = preferredNames.indices.filter { collidingNames.contains(preferredNames[$0]) || hiddenEntries.contains($0) }
		let disambiguatedNames = identifierSafeNames(
			for: collidingIndices.map { index in
				(label: preferredNames[index], suffixTypes: [typeDescriptions[index].simplified, typeDescriptions[index]])
			},
			reservedNames: namesInScope.union(reservedNames).union(preferredNames),
		)
		var names = preferredNames
		for (index, name) in zip(collidingIndices, disambiguatedNames) {
			names[index] = name
		}
		return names
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
	static func disambiguatedLabel(
		for node: MockParameterNode,
		labelMap: [String: [TypeDescription: String]],
	) -> String {
		// safedi-source-rule: allow forceUnwrap — every caller passes the `labelMap` that `disambiguatePropertyLabels` made of nodes that include `node`, and it names each of them.
		labelMap[node.propertyLabel]![node.typeDescription]!
	}

	/// Names apart entries that share a label, deriving every name from type structure so that
	/// each is a valid Swift identifier no matter how its types are spelled.
	///
	/// Each entry lists suffix types in order of preference. An entry is named
	/// `<label>_<suffix type’s asIdentifier>` with the first suffix type whose `asIdentifier`
	/// no other entry with its label shares at the same position, nor any of
	/// `entriesKeepingTheirNames` with its label, or with its last suffix type when every position
	/// is shared. Then, in entry order, underscores are appended until the name is neither reserved
	/// nor already given to an earlier entry. `entriesKeepingTheirNames` are not named: they list
	/// their suffix types only so that an entry is named apart from them as from a sibling, and
	/// list as many as each entry.
	///
	/// - Parameter step: The step whose work the naming counts as (`GenerationWork`), or `nil` where it is not counted: the
	///   callers that name builder functions and a mock's parameters as code is emitted, which no test of the work measures.
	static func identifierSafeNames(
		for entries: [(label: String, suffixTypes: [TypeDescription])],
		besideEntriesKeepingTheirNames entriesKeepingTheirNames: [(label: String, suffixTypes: [TypeDescription])] = [],
		reservedNames: Set<String>,
		countingWorkAs step: GenerationWork.Step? = nil,
	) -> [String] {
		let suffixesPerEntry = entries.map { $0.suffixTypes.map(\.asIdentifier) }
		// How many entries share each label and suffix at each position, and the suffixes of the entries keeping their
		// names, found once for every entry to look up: scanning every entry for every entry grew with the square of the
		// entries, which a seam with a place at thousands of sites has.
		var entryCounts = [LabeledSuffix: Int]()
		for (entry, suffixes) in zip(entries, suffixesPerEntry) {
			for (position, suffix) in suffixes.enumerated() {
				entryCounts[LabeledSuffix(label: entry.label, position: position, suffix: suffix), default: 0] += 1
			}
		}
		var suffixesKeepingTheirNames = Set<LabeledSuffix>()
		for entry in entriesKeepingTheirNames {
			for (position, suffixType) in entry.suffixTypes.enumerated() {
				suffixesKeepingTheirNames.insert(LabeledSuffix(label: entry.label, position: position, suffix: suffixType.asIdentifier))
			}
		}
		GenerationWork.record(suffixesPerEntry.joined().count + entriesKeepingTheirNames.map(\.suffixTypes.count).reduce(0, +), by: step)
		let sharedEntryCounts = GenerationWork.Shared(entryCounts)
		let sharedSuffixesKeepingTheirNames = GenerationWork.Shared(suffixesKeepingTheirNames)
		var takenNames = reservedNames
		return entries.indices.map { index in
			let suffixes = suffixesPerEntry[index]
			let suffix = suffixes.indices.first { position in
				let entryCountBySuffix = GenerationWork.taking(sharedEntryCounts, by: step)
				let suffixesOfEntriesKeepingTheirNames = GenerationWork.taking(sharedSuffixesKeepingTheirNames, by: step)
				let labeledSuffix = LabeledSuffix(label: entries[index].label, position: position, suffix: suffixes[position])
				// The entry itself is the one entry with its label and suffix at this position.
				return entryCountBySuffix[labeledSuffix, default: 0] == 1 && !suffixesOfEntriesKeepingTheirNames.contains(labeledSuffix)
			}.map { suffixes[$0] } ?? suffixes[suffixes.count - 1]
			var name = "\(entries[index].label)_\(suffix)".spelledAsJoinedIdentifier
			while takenNames.contains(name) {
				name = "\(name)_".spelledAsJoinedIdentifier
			}
			takenNames.insert(name)
			return name
		}
	}

	/// A suffix an entry of `identifierSafeNames(for:besideEntriesKeepingTheirNames:reservedNames:countingWorkAs:)` could be
	/// named with: its label, the suffix type's position among the entry's, and that type's `asIdentifier`.
	private struct LabeledSuffix: Hashable {
		let label: String
		let position: Int
		let suffix: String
	}

	/// Collects all unique types from the `MockParameterNode` tree, deduplicated
	/// by `concreteType`. Returns nodes in depth-first order (children before
	/// parents) so that referenced types appear before their referrers.
	/// Uses `concreteType` (not `instantiatedTypeDescription`) because config
	/// structs are nested in concrete type extensions — protocol extensions
	/// cannot contain nested type declarations.
	/// When the same type appears in both sendable and non-sendable contexts,
	/// the sendable version is preferred (`@Sendable` closures work in both contexts).
	/// `async` for the reason `generateMockBodyBindings` is.
	///
	/// A node whose type repeats an ancestor's records nothing: its ancestor's node records the type. The nodes beneath it
	/// are walked all the same, since a type can be built only there, and each is recorded apart, in
	/// `nodesBeneathRepeatedAncestors`, when `readsConfigurationBeneathRepeatedAncestor` says the code generated for it
	/// reads its type's configuration. A cycle edge prunes every such node (the path from the ancestor to the node that
	/// repeats it is a cycle of types, which `computeCycleEdges` breaks at one of its edges), so no override reaches it.
	/// One node is kept per type and construction, since `generateMockCode` chooses between a type's constructions there,
	/// and adds the configurations those structs nest.
	private static func collectUniqueConfigurationTypes(
		from nodes: [MockParameterNode],
		readsConfigurationBeneathRepeatedAncestor: (MockParameterNode) -> Bool,
	) async -> ConfigurationTypes {
		var seen = Set<String>()
		var result = [MockParameterNode]()
		var nodesBeneathRepeatedAncestors = [MockParameterNode]()

		func walk(_ node: MockParameterNode, ancestorTypes: Set<String>, isBeneathRepeatedAncestor: Bool) async {
			let key = node.concreteType.asSource
			let repeatsAncestor = ancestorTypes.contains(key)
			var childAncestors = ancestorTypes
			childAncestors.insert(key)
			// Process children first (depth-first). Only property children
			// produce configuration structs; aliases are plain `let` bindings.
			for child in node.propertyChildren {
				await walk(child, ancestorTypes: childAncestors, isBeneathRepeatedAncestor: isBeneathRepeatedAncestor || repeatsAncestor)
			}
			// Skip leaf nodes that don't need a SafeDIMockConfiguration struct, and nodes whose type repeats an ancestor's,
			// such as a cycle-closer (isPropertyCycle == true), whose property appears earlier in the stack.
			guard node.needsConfigurationStruct, !repeatsAncestor else { return }
			if isBeneathRepeatedAncestor {
				if readsConfigurationBeneathRepeatedAncestor(node) {
					nodesBeneathRepeatedAncestors.append(node)
				}
			} else if seen.contains(key) {
				// If this node requires sendable and the existing one doesn't,
				// replace it — @Sendable closures are compatible in both contexts.
				if node.requiresSendable,
				   let existingIndex = result.firstIndex(where: {
				   	$0.concreteType.asSource == key && !$0.requiresSendable
				   })
				{
					result[existingIndex] = node
				}
			} else {
				seen.insert(key)
				result.append(node)
			}
		}

		for node in nodes {
			await walk(node, ancestorTypes: [], isBeneathRepeatedAncestor: false)
		}
		// A type the tree also records above every repeated ancestor is generated from that node.
		var seenConstructions = Set<ConstructedType>()
		return ConfigurationTypes(
			nodes: result,
			nodesBeneathRepeatedAncestors: nodesBeneathRepeatedAncestors.filter { node in
				!seen.contains(node.concreteType.asSource)
					&& seenConstructions.insert(ConstructedType(concreteType: node.concreteType, usesMockInitializer: node.useMockInitializer)).inserted
			},
		)
	}

	/// The children of `node` whose `SafeDIMockConfiguration` the struct generated from `node` nests as a field
	/// (`configurationField(of:named:parentRequiresSendable:sendableConfigurationTypeNames:)`): each that no edge in
	/// `cycleEdges` prunes, that needs a struct, and that calls no other module's public mock taking `safeDIOverrides`.
	static func childrenWithNestedConfigurations(of node: MockParameterNode, cycleEdges: Set<CycleEdge>) -> [MockParameterNode] {
		node.propertyChildren.filter { child in
			!cycleEdges.contains(CycleEdge(parent: node.concreteType.asSource, child: child.concreteType.asSource))
				&& child.publicMockCall?.takesOverrides != true
				&& child.needsConfigurationStruct
		}
	}

	/// Generates the `SafeDIOverrides` struct. Configuration type references
	/// use qualified names (e.g., `ChildA.SafeDIMockConfiguration`).
	///
	/// The field of each root-level child is in the struct's storage (`ConfigurationStorage`). An override of what the
	/// mock receives only if available is stored on the struct itself: its type is the user's, which SafeDI cannot prove
	/// `Sendable`, so stored beside the storage it keeps the struct `Sendable` exactly where that type is, as the struct
	/// was when it stored every field. No such override is a configuration, so the struct still holds no configuration
	/// by value.
	private static func generateSafeDIOverridesStruct(
		rootChildren: [MockParameterNode],
		rootLabelMap: [String: [TypeDescription: String]],
		onlyIfAvailableOverrides: [OnlyIfAvailableOverride],
		sendableConfigurationTypeNames: Set<String>,
		indent: String,
	) -> String {
		let innerIndent = "\(indent)\(standardIndent)"
		let memberIndent = "\(innerIndent)\(standardIndent)"

		var lines = [String]()
		lines.append("\(indent)/// Overrides for the mock dependency tree.")
		lines.append("\(indent)struct \(ReservedName.mockOverridesTypeName) {")

		// A child whose call can hand its override closure no builder a person writes has no member
		// (`MockParameterNode.offersOverrideClosure`); the struct stays, with an initializer that takes nothing where it has
		// no other member.
		let rootChildren = MockParameterNode.inInlineOrder(rootChildren.filter(\.offersOverrideClosure))
		guard !rootChildren.isEmpty || !onlyIfAvailableOverrides.isEmpty else {
			lines.append("\(innerIndent)init() {}")
			lines.append("\(indent)}")
			return lines.joined(separator: "\n")
		}

		// Generate SafeDIOverrides init with root-level children and onlyIfAvailable entries.
		let childFields = rootChildren.map { child in
			configurationField(
				of: child,
				named: disambiguatedLabel(for: child, labelMap: rootLabelMap),
				parentRequiresSendable: false,
				sendableConfigurationTypeNames: sendableConfigurationTypeNames,
			)
		}
		let storage = ConfigurationStorage(fields: childFields.map(\.field))
		lines.append("\(innerIndent)init(")
		// Each parameter is named apart from `self`, which would hide the instance the overrides of what the mock receives only
		// if available are assigned to.
		var initParameters = childFields.map { "\(memberIndent)\($0.field.name.spelledAsAssigningParameter(labeled: $0.field.name)): \($0.field.typeSource) = \($0.defaultValue)" }
		for onlyIfAvailableOverride in onlyIfAvailableOverrides {
			initParameters.append("\(memberIndent)\(onlyIfAvailableOverride.name.spelledAsAssigningParameter(labeled: onlyIfAvailableOverride.name)): \(onlyIfAvailableOverride.typeDescription.asSource) = nil")
		}
		lines.append(initParameters.joined(separator: ",\n"))
		lines.append("\(innerIndent)) {")
		if !storage.fields.isEmpty {
			lines.append(contentsOf: storage.initialization(to: storage.fields.map(\.name.spelledAsAssigningParameterName), indent: memberIndent))
		}
		for onlyIfAvailableOverride in onlyIfAvailableOverrides {
			lines.append("\(memberIndent)self.\(onlyIfAvailableOverride.name) = \(onlyIfAvailableOverride.name.spelledAsAssigningParameterName)")
		}
		lines.append("\(innerIndent)}")

		// Generate the properties: those the storage holds, then the overrides of what the mock receives only if available.
		lines.append("")
		lines.append(contentsOf: storage.readers(indent: innerIndent))
		for onlyIfAvailableOverride in onlyIfAvailableOverrides {
			lines.append("\(innerIndent)let \(onlyIfAvailableOverride.name.spelledAsMemberDeclarationName): \(onlyIfAvailableOverride.typeDescription.asSource)")
		}
		if !storage.fields.isEmpty {
			lines.append("")
			lines.append(contentsOf: storage.declarations(indent: innerIndent))
		}

		lines.append("\(indent)}")
		return lines.joined(separator: "\n")
	}

	/// The field of a configuration that configures how `child` is built, and the default of the initializer parameter
	/// that sets it: the `SafeDIOverrides` of the public mock `child` calls, `child`'s own configuration when it has one,
	/// or else an optional builder closure.
	/// - Parameters:
	///   - parentRequiresSendable: Whether the configuration that holds the field is `@Sendable`-typed, which makes each
	///     of its closures `@Sendable`, as `child` being built in a `@Sendable` builder function does.
	///   - sendableConfigurationTypeNames: The types whose configurations are `@Sendable`-typed, and so `Sendable`.
	private static func configurationField(
		of child: MockParameterNode,
		named name: String,
		parentRequiresSendable: Bool,
		sendableConfigurationTypeNames: Set<String>,
	) -> (field: ConfigurationStorage.Field, defaultValue: String) {
		let isSendable = parentRequiresSendable || child.requiresSendable
		let (typeSource, defaultValue, isProvenSendable) = if let publicMockOverridesMember = child.publicMockOverridesMember(sendable: isSendable) {
			// A `@Sendable` closure that returns the overrides where the child is built in a `@Sendable` builder function,
			// and otherwise the overrides, a public struct, which is never `Sendable`.
			(publicMockOverridesMember.type, publicMockOverridesMember.defaultValue, isSendable)
		} else if child.needsConfigurationStruct {
			(child.configurationTypeName, ".init()", sendableConfigurationTypeNames.contains(child.concreteType.asSource))
		} else {
			// A leaf child field also needs `@Sendable` when the child itself
			// is reached sendably — e.g. a `SendableInstantiator` dependency on
			// a non-sendable parent. `generateInstantiatorBinding` later wraps
			// such children in a `@Sendable` local function, which would fail
			// to capture a non-sendable override closure.
			("(\(isSendable ? "@Sendable " : "")\(child.builderClosureType))?", "nil", isSendable)
		}
		return (
			field: ConfigurationStorage.Field(
				name: name,
				typeSource: typeSource,
				parameterTypeSource: typeSource,
				accessPrefix: "",
				documentation: nil,
				isProvenSendable: isProvenSendable,
			),
			defaultValue: defaultValue,
		)
	}

	/// Generates a single `SafeDIMockConfiguration` struct for a `MockParameterNode`.
	/// Closure fields are marked `@Sendable` only when `requiresSendable` is `true` —
	/// i.e., the struct's concrete type is referenced from a `SendableInstantiator`
	/// scope in at least one root. The flag is computed once across all roots so
	/// cross-root struct-per-type dedup produces a consistent annotation. Such a struct
	/// also stores each labeled default-valued parameter that is not a closure as a
	/// `@Sendable` closure returning the value, which `resolveBuilderArguments` calls.
	///
	/// Its fields are in its storage (`ConfigurationStorage`), which is `Sendable` when the struct is `@Sendable`-typed and
	/// each configuration it holds is too, as the struct was when it stored its fields.
	private static func generateConfigurationStruct(
		for node: MockParameterNode,
		indent: String,
		cycleEdges: Set<CycleEdge>,
		requiresSendable: Bool,
		sendableConfigurationTypeNames: Set<String>,
		defaultExpression: (MockParameterNode.DefaultParameter) -> String,
	) -> String {
		let innerIndent = "\(indent)\(standardIndent)"
		let sendableAnnotation = requiresSendable ? "@Sendable " : ""
		var lines = [String]()

		lines.append("\(indent)/// Configuration for how this type is constructed within a mock tree.")
		// Not `nonisolated`, unlike a public mock's configuration (`publicConfigurationDeclarations`): its initializer spells
		// the defaults the configured type's declaration spells, which may read the state of the actor the type is on. So in a
		// module whose declarations default to the main actor, the configuration of a type on the main actor is there too.
		lines.append("\(indent)struct \(MockParameterNode.configurationStructName) {")

		// Build init parameters in order: children, defaults, builder (last).
		var initParameters = [String]()
		var fields = [ConfigurationStorage.Field]()
		func appendField(named name: String, typeSource: String, parameterTypeSource: String, isProvenSendable: Bool, documentation: String? = nil) {
			fields.append(ConfigurationStorage.Field(
				name: name,
				typeSource: typeSource,
				parameterTypeSource: parameterTypeSource,
				accessPrefix: "",
				documentation: documentation,
				isProvenSendable: isProvenSendable,
			))
		}

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
		// A child whose call can hand its override closure no builder a person writes has no member
		// (`MockParameterNode.offersOverrideClosure`).
		for child in MockParameterNode.inInlineOrder(nonCycleChildren) where child.offersOverrideClosure {
			let (field, defaultValue) = configurationField(
				of: child,
				named: disambiguatedLabel(for: child, labelMap: childLabelMap),
				parentRequiresSendable: requiresSendable,
				sendableConfigurationTypeNames: sendableConfigurationTypeNames,
			)
			initParameters.append("\(innerIndent)\(standardIndent)\(field.name): \(field.typeSource) = \(defaultValue)")
			fields.append(field)
		}

		// Default-valued parameters.
		for defaultParameter in node.defaultParameters {
			let typeSource = defaultParameter.valueTypeDescription.asSource
			// Only add @Sendable if this struct requires it AND the type isn't already `@Sendable` at its top: a closure that
			// takes or returns a `@Sendable` function, which its spelling mentions, is not itself `@Sendable`.
			let closureSendable = (requiresSendable && !defaultParameter.valueTypeDescription.isSendableFunction) ? "@Sendable " : ""
			if defaultParameter.isAutoclosure, !requiresSendable {
				// An `@autoclosure` parameter is evaluated where the type is built: the struct stores a closure that
				// returns the value, which its initializer takes as an autoclosure, as the parameter does, and the mock
				// calls it once per construction (`resolveBuilderArguments`).
				initParameters.append("\(innerIndent)\(standardIndent)\(defaultParameter.label): @autoclosure @escaping () -> \(typeSource) = \(autoclosureDefault(defaultExpression(defaultParameter)))")
				appendField(named: defaultParameter.label, typeSource: "() -> \(typeSource)", parameterTypeSource: "@escaping () -> \(typeSource)", isProvenSendable: false)
			} else if defaultParameter.isClosureType, !defaultParameter.isAutoclosure {
				initParameters.append("\(innerIndent)\(standardIndent)\(defaultParameter.label): \(closureSendable)@escaping \(typeSource) = \(defaultExpression(defaultParameter))")
				// Where the struct requires it, the stored function type is `@Sendable` at its top, by the attribute added here
				// or by its own spelling, so the storage is proven `Sendable`.
				appendField(
					named: defaultParameter.label,
					typeSource: "\(closureSendable)\(typeSource)",
					parameterTypeSource: "\(closureSendable)@escaping \(typeSource)",
					isProvenSendable: requiresSendable,
				)
			} else if requiresSendable {
				// A `@Sendable` builder function cannot capture the value when its type is not `Sendable`, and
				// SafeDI cannot tell whether it is, so the struct stores a `@Sendable` closure that returns the
				// value and the mock calls it where it builds the type, which evaluates the default once per
				// construction, as production does. The initializer takes the value as an autoclosure, so a
				// caller still passes a value. Swift rejects `@Sendable` on a typealias, so a typealiased function
				// type is stored this way too, even when the parameter is declared `@escaping`.
				initParameters.append("\(innerIndent)\(standardIndent)\(defaultParameter.label): @autoclosure @escaping @Sendable () -> \(typeSource) = \(autoclosureDefault(defaultExpression(defaultParameter)))")
				appendField(named: defaultParameter.label, typeSource: "@Sendable () -> \(typeSource)", parameterTypeSource: "@escaping @Sendable () -> \(typeSource)", isProvenSendable: true)
			} else {
				// A parameter declared `@escaping` is of a function type, which the initializer stores, so it takes the
				// value `@escaping` too, also when the type is a typealias of a function type.
				let escaping = defaultParameter.isDeclaredEscaping ? "@escaping " : ""
				initParameters.append("\(innerIndent)\(standardIndent)\(defaultParameter.label): \(escaping)\(typeSource) = \(defaultExpression(defaultParameter))")
				appendField(named: defaultParameter.label, typeSource: typeSource, parameterTypeSource: "\(escaping)\(typeSource)", isProvenSendable: false)
			}
		}

		// Builder parameter (always last, unlabeled). Optional with nil default so that
		// the default construction (which may be @MainActor) is called in mock()
		// rather than referenced in this nonisolated init.
		let builderType = "(\(sendableAnnotation)\(node.concreteBuilderClosureType))?"
		initParameters.append("\(innerIndent)\(standardIndent)_ \(ReservedName.configurationBuilderPropertyName): \(builderType) = nil")
		appendField(
			named: ReservedName.configurationBuilderPropertyName,
			typeSource: builderType,
			parameterTypeSource: builderType,
			isProvenSendable: requiresSendable,
			documentation: "Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.",
		)
		let storage = ConfigurationStorage(fields: fields)

		// Emit init.
		lines.append("\(innerIndent)init(")
		lines.append(initParameters.joined(separator: ",\n"))
		lines.append("\(innerIndent)) {")
		lines.append(contentsOf: storage.initialization(to: fields.map(\.name), indent: "\(innerIndent)\(standardIndent)"))
		lines.append("\(innerIndent)}")

		// Emit the properties that read each field from the storage, and the storage. A field is a computed property, so an
		// initializer a person writes in an extension calls `self.init(…)`, as the Manual asks (see "Configuration fields are
		// behind one reference" in `.claude/rules/mock-generation.md`).
		lines.append("")
		lines.append(contentsOf: storage.readers(indent: innerIndent))
		lines.append("")
		lines.append(contentsOf: storage.declarations(indent: innerIndent))

		lines.append("\(indent)}")
		return lines.joined(separator: "\n")
	}

	/// `expression` as the default of an `@autoclosure` parameter: parenthesized when it is a closure literal, which
	/// Swift otherwise reads as the autoclosure itself, so that `(() -> Void)? = {}` would declare a closure that
	/// returns `()`. In parentheses, it is the value the autoclosure returns.
	static func autoclosureDefault(_ expression: String) -> String {
		var parser = Parser(expression)
		return if ExprSyntax.parse(from: &parser).is(ClosureExprSyntax.self) {
			"(\(expression))"
		} else {
			expression
		}
	}

	// MARK: Mock Body Generation

	/// Reads `safeDIOverrides` values into locals declared before the outermost
	/// `@Sendable` builder function of a sendable subtree.
	///
	/// `SafeDIOverrides` is not `Sendable` whenever any of its stored closures
	/// is not, so code lexically inside a `@Sendable` function — at any depth,
	/// including inside builder functions of nested instantiators — must not
	/// reference it. Every value in a sendable subtree's configuration is
	/// `Sendable`: its closures are generated `@Sendable`, and each of its
	/// defaults is stored as a `@Sendable` closure that the function calls
	/// (`generateConfigurationStruct`). So each value is read into a local
	/// outside the function and the function captures the local instead.
	///
	/// The mock body walk asks the extractor for a local each time it would
	/// otherwise read `safeDIOverrides`, so every extracted local has exactly
	/// one reader. A node's own arguments are read through an enclosing
	/// extractor exactly once, where the node's parent computes them. The
	/// builder that created the extractor then emits the recorded
	/// `let <localName> = <expression>` lines before its function.
	///
	/// A local is named after the function and the override's path, its labels
	/// joined with underscores, which labels may hold too: `header.leaf` and
	/// `header_leaf` join to one name, and a sibling labeled
	/// `screenBuilder__safeDIBuilder` declares the function a local of
	/// `screenBuilder` would be named. So each local is claimed from `names`, the
	/// allocator of the scope the locals are declared in, which holds that scope's
	/// names and those of each scope inside the function the walk has entered,
	/// where the local is read (`reserve(_:)`). A builder function of a scope
	/// enclosing that one needs no reservation: it builds a property on the
	/// override's path, whose label every local of the function spells after
	/// the function's own.
	final class SendableOverrideExtractor {
		init(functionName: String, names: GeneratedNameAllocator) {
			self.functionName = functionName
			self.names = names
		}

		/// Records that `expression` is read into a local named after the
		/// outermost `@Sendable` function, and returns that local's name.
		func extract(_ expression: String, localNameSuffix: String) -> String {
			let localName = names.claim("\(functionName)__\(localNameSuffix)".spelledAsJoinedIdentifier)
			extractions.append((localName: localName, expression: expression))
			return localName
		}

		/// Keeps every later local apart from `names`, which a scope inside the function declares: a local named as one
		/// would be hidden by it where it is read.
		func reserve(_ names: some Sequence<String>) {
			self.names.reserve(names)
		}

		/// The `(localName, expression)` pairs recorded so far, in the order
		/// they were extracted.
		private(set) var extractions = [(localName: String, expression: String)]()

		/// The names of the scope the locals are declared in, the locals among them.
		private(set) var names: GeneratedNameAllocator

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
	/// scope whose body holds `items`. `propertyNodeLabelMap` names the property nodes among
	/// `items`, as `disambiguatePropertyLabels` does; the mock root passes the names its scope
	/// chose apart from the names declared beneath it. `sendableAutoclosureParameters` are the
	/// `mock()` parameters taken as `@Sendable` autoclosures (`SendableAutoclosureParameter`),
	/// which a node that instantiates one binds where it is built (`sendableAutoclosureBindings`).
	/// This method and `generateInstantiatorBinding` call one another for each level of the
	/// tree, which can be as deep as the module has types. They are `async` so that their frames
	/// are allocated with the task rather than on the thread's stack, which could not hold them.
	private static func generateMockBodyBindings(
		items: [MockTreeItem],
		propertyNodeLabelMap: [String: [TypeDescription: String]]? = nil,
		parentPath: String,
		indent: String,
		ancestorTypes: Set<String> = [],
		sendableOverrideExtractor: SendableOverrideExtractor? = nil,
		flatParameterDisambiguationMap: [String: [TypeDescription: String]] = [:],
		enclosingFunctionNames: [BuiltDeclaration: String] = [:],
		lazilyInstantiatedBindingNames: [String: [TypeDescription: String]] = [:],
		uncoveredDependencyNames: [String: [TypeDescription: String]] = [:],
		sendableAutoclosureParameters: [Property: SendableAutoclosureParameter],
		parentConcreteType: String?,
		cycleEdges: Set<CycleEdge>,
		overridePathReachable: Bool,
		handWrittenMockDefaultParameters: [TypeDescription: [MockParameterNode.DefaultParameter]],
		sendableConfigurationTypeNames: Set<String>,
		publicMock: PublicMockEmission? = nil,
		enclosingBindingNamesPassedByName: [String: String] = [:],
	) async -> [String] {
		var lines = [String]()

		// Disambiguate sibling labels at this level (property children only —
		// aliases don't participate in sibling disambiguation).
		let propertyNodes = items.propertyNodes
		let labelMap = propertyNodeLabelMap ?? disambiguatePropertyLabels(for: propertyNodes)
		// Each builder function is named after its disambiguated label, unless a cycle-closing
		// scope beneath this level refers to an enclosing function of that name.
		// Nearly every level holds no node of a cycle, and its nodes keep their names.
		// A hole held in a wrapper declares a builder function too, which those scopes must not resolve to.
		let holeSitesBuildingWrappers = items.holeSitesBuildingWrappers
		func builderFunctionCandidates() -> [BuilderFunctionCandidate] {
			propertyNodes.map { node in
				let disambiguated = disambiguatedLabel(for: node, labelMap: labelMap)
				return BuilderFunctionCandidate(
					property: node.property,
					declaration: BuiltDeclaration(property: node.property, concreteType: node.concreteType),
					name: disambiguated == node.propertyLabel ? nil : Self.functionName(toBuildPropertyNamed: disambiguated),
					declaresFunction: !node.isPropertyCycle,
					cycleClosedOnDeclarations: node.cycleClosedOnDeclarations,
					isReferencedByCycleClosingScope: node.isReferencedByCycleClosingScope,
					referencedFillNames: node.referencedFillNames,
				)
			} + holeSitesBuildingWrappers.map { alias in
				BuilderFunctionCandidate(
					property: alias.property,
					declaration: BuiltDeclaration(property: alias.property, concreteType: alias.property.typeDescription.asInstantiatedType),
					name: nil,
					declaresFunction: true,
					cycleClosedOnDeclarations: [],
					isReferencedByCycleClosingScope: false,
					referencedFillNames: [],
				)
			}
		}
		let builderFunctionNamesByNode = propertyNodes.contains(where: { !$0.cycleClosedOnDeclarations.isEmpty || $0.isReferencedByCycleClosingScope })
			? builderFunctionNames(for: builderFunctionCandidates(), enclosingFunctionNames: enclosingFunctionNames)
			: nil
		var propertyNodeIndex = 0
		var holeSiteBuildingWrapperIndex = 0

		// The builder functions this scope declares. A local a `@Sendable` function started here reads an override into is
		// declared beside them, and one an enclosing `@Sendable` function reads is hidden by them where this scope reads it.
		var builderFunctionNamesDeclaredHere = Set<String>()
		for (index, node) in propertyNodes.enumerated() where !node.isPropertyCycle {
			builderFunctionNamesDeclaredHere.insert(builderFunctionNamesByNode?[index].functionName ?? Self.functionName(toBuildPropertyNamed: disambiguatedLabel(for: node, labelMap: labelMap)))
		}
		for (index, alias) in holeSitesBuildingWrappers.enumerated() {
			builderFunctionNamesDeclaredHere.insert(builderFunctionNamesByNode?[propertyNodes.count + index].functionName ?? alias.holeSite?.wrapperFunctionName ?? Self.functionName(toBuild: alias.property))
		}
		if let sendableOverrideExtractor {
			// A node's override and arguments are read here, through the enclosing extractor, before the walk enters the
			// node's builder function, where the node is constructed: so the functions declared there, under the names
			// they have unless a cycle renames them, are reserved now too.
			sendableOverrideExtractor.reserve(builderFunctionNamesDeclaredHere)
			for node in propertyNodes {
				let childNodes = node.children.propertyNodes
				let childLabelMap = disambiguatePropertyLabels(for: childNodes)
				sendableOverrideExtractor.reserve(childNodes.map { Self.functionName(toBuildPropertyNamed: disambiguatedLabel(for: $0, labelMap: childLabelMap)) })
			}
		}
		// The names of this scope, from which each `@Sendable` function started here claims the locals it reads overrides
		// into: the functions declared here, and the locals the mock's body reads its `@Sendable` autoclosure parameters into,
		// which the scopes inside the function call.
		var overrideLocalNames = GeneratedNameAllocator(reserving: builderFunctionNamesDeclaredHere)
		overrideLocalNames.reserve(sendableAutoclosureParameters.values.map(\.localName))

		// Merge sibling-level disambiguations into the receiver-disambiguation
		// map so consumers can rebind colliding sibling names back to their raw
		// labels via `emitReceiverBindings`, and construction arguments resolve
		// via Swift lexical scoping inside a wrapper function body.
		var combinedDisambiguationMap = flatParameterDisambiguationMap
		mergeSiblingDisambiguations(into: &combinedDisambiguationMap, for: propertyNodes, labelMap: labelMap)

		/// The name of the builder function of the property node at `nodeIndex` among `propertyNodes`, `node`, whose binding
		/// is named `bindingName`: the function a cycle-closing node refers to, or the one any other declares.
		func functionName(ofNodeAt nodeIndex: Int, _ node: MockParameterNode, bindingName: String) -> String {
			let builderFunctionNames = builderFunctionNamesByNode?[nodeIndex] ?? BuilderFunctionNames()
			return if node.isPropertyCycle {
				node.closedOnDeclaration.flatMap { builderFunctionNames.enclosingFunctionNames[$0] } ?? Self.functionName(toBuild: node.property)
			} else {
				builderFunctionNames.functionName ?? Self.functionName(toBuildPropertyNamed: bindingName)
			}
		}
		let loopMembers = loopMemberEmissions(
			of: items,
			propertyNodes: propertyNodes,
			bindingName: { disambiguatedLabel(for: $0, labelMap: labelMap) },
			functionName: functionName(ofNodeAt:_:bindingName:),
			// The level's other functions in scope: the enclosing functions and fills a node beneath refers to by name, and
			// the functions of the holes the level builds in wrappers.
			otherNamesInScope: {
				functionNamesReferenced(beneath: builderFunctionCandidates(), enclosingFunctionNames: enclosingFunctionNames)
					.union(holeSitesBuildingWrappers.indices.map { builderFunctionNamesByNode?[propertyNodes.count + $0].functionName ?? Self.functionName(toBuild: holeSitesBuildingWrappers[$0].property) })
			},
			publicMock: publicMock,
			indent: "\(indent)\(standardIndent)",
		)
		// The members of the loop of builders being emitted, which are emitted as one unit when it ends (see
		// `InstantiatorBindingLines`). The members of a loop are consecutive items.
		var loopUnit: (loop: Int, lines: InstantiatorBindingLines)?
		func appendToLoopUnit(_ loop: Int, _ memberLines: InstantiatorBindingLines) {
			var unitLines = loopUnit?.lines ?? InstantiatorBindingLines()
			unitLines.prelude.append(contentsOf: memberLines.prelude)
			unitLines.function.append(contentsOf: memberLines.function)
			unitLines.binding.append(contentsOf: memberLines.binding)
			loopUnit = (loop, unitLines)
		}
		func emitLoopUnit() {
			if let loopUnit {
				lines.append(contentsOf: loopUnit.lines.all)
			}
			loopUnit = nil
		}

		for item in items {
			let itemLoop = switch item {
			case let .alias(alias):
				alias.loop
			case let .property(node):
				node.loop
			}
			if itemLoop != loopUnit?.loop {
				emitLoopUnit()
			}
			switch item {
			case let .alias(alias):
				var holeFunctionName: String?
				if let holeSite = alias.holeSite, !holeSite.property.propertyType.isConstant {
					holeFunctionName = builderFunctionNamesByNode?[propertyNodes.count + holeSiteBuildingWrapperIndex].functionName
					holeSiteBuildingWrapperIndex += 1
				}
				let aliasBinding = emitAliasBinding(
					alias,
					holeFunctionName: holeFunctionName,
					flatParameterDisambiguationMap: combinedDisambiguationMap,
					lazilyInstantiatedBindingNames: lazilyInstantiatedBindingNames,
					indent: indent,
				)
				if let loop = alias.loop {
					appendToLoopUnit(loop, InstantiatorBindingLines(binding: [aliasBinding]))
				} else {
					lines.append(aliasBinding)
				}
			case let .property(node):
				// The payloads of the cases nested by type that lead through this node's property to a place are bound just
				// before it is built, as a seam's tree binds them (`SeamHoles`); an instantiator's binding makes these calls
				// itself, just before its builder function.
				if !node.isInstantiator {
					for valuesBinding in node.valuesBindings {
						lines.append("\(indent)\(valuesBinding.line(bindingNamesPassedByName: enclosingBindingNamesPassedByName, lazilyInstantiatedBindingNames: lazilyInstantiatedBindingNames))")
					}
				}
				// A call that fills builders is made in a builder function of its own, which declares the fills and names
				// the guard first, as a seam call's function does (`callPreamble(of:indent:)`); any other call names the
				// guard where it is made.
				if let publicMockCall = node.publicMockCall, node.fillingGenerator == nil {
					lines.append("\(indent)\(publicMockCall.guardLine(for: node.concreteType))")
				}
				let nodeTypeKey = node.cycleNodeKey
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
				// A cycle-closing node declares no function: it refers to the enclosing one of the declaration it repeats.
				let functionName = functionName(ofNodeAt: propertyNodeIndex - 1, node, bindingName: disambiguated)

				let relativePath = GeneratedCodeText.overrideRelativePath(of: nodePath)

				// The optional override closure to consult, or `nil` when there is
				// none to consult: a cycle node constructs itself directly, and a
				// node whose override path was pruned from its parent's
				// `SafeDIMockConfiguration` has no override slot to read. Inside a
				// `@Sendable` function the override is read into a local outside
				// that function, so reference that local instead.
				// A node whose call of another module's public mock can hand no builder a person writes offers no closure, a
				// deliberate gap commented where the member is typed (`MockParameterNode.offersOverrideClosure`).
				let overrideExpression: String? = if isCycleNode || !thisOverrideReachable || !node.offersOverrideClosure {
					nil
				} else if let sendableOverrideExtractor {
					sendableOverrideExtractor.extract(
						node.overridePath(nodePath: nodePath),
						localNameSuffix: "\(relativePath)_\(ReservedName.configurationBuilderPropertyName)",
					)
				} else {
					node.overridePath(nodePath: nodePath)
				}

				let nodeHandWrittenMockDefaultParameters = handWrittenMockDefaultParameters[node.concreteType, default: []]
				// A node that declares the builder function a cycle closes on is constructed inside that function, whose
				// parameters hide the bindings of their labels. Its arguments are read here once, through the extractor of
				// an enclosing `@Sendable` function if any, so each override read has one local.
				let argumentLazilyInstantiatedBindingNames = !node.isPropertyCycle && !node.cycleParameters.isEmpty
					? builderLazilyInstantiatedBindingNames(for: node, from: lazilyInstantiatedBindingNames)
					: lazilyInstantiatedBindingNames
				let bindingNamesPassedByName = receivedBindingNamesPassedByName(
					to: node,
					flatParameterDisambiguationMap: combinedDisambiguationMap,
					lazilyInstantiatedBindingNames: lazilyInstantiatedBindingNames,
				)
				let arguments = mockBuilderArguments(
					for: node,
					nodePath: nodePath,
					lazilyInstantiatedBindingNames: argumentLazilyInstantiatedBindingNames,
					uncoveredDependencyNames: uncoveredDependencyNames,
					sendableOverrideExtractor: sendableOverrideExtractor,
					overrideReachable: thisOverrideReachable,
					handWrittenMockDefaultParameters: nodeHandWrittenMockDefaultParameters,
					sendableConfigurationTypeNames: sendableConfigurationTypeNames,
					publicMock: publicMock,
					bindingNamesPassedByName: bindingNamesPassedByName,
				)
				// The member that configures a node calling another module's public mock is a `@Sendable` closure where
				// the struct holding it is read inside a `@Sendable` builder function.
				let publicMockOverridesIsSendableClosure = node.requiresSendable || (parentConcreteType.map(sendableConfigurationTypeNames.contains) ?? false)
				/// The expression that builds the node, on a line at `lineIndent`.
				func construction(at lineIndent: String) -> String {
					mockConstructionExpression(
						for: node,
						overrideExpression: overrideExpression,
						arguments: arguments,
						overrideReachable: thisOverrideReachable,
						handWrittenMockDefaultParameters: nodeHandWrittenMockDefaultParameters,
						publicMock: publicMock,
						publicMockOverridesIsSendableClosure: publicMockOverridesIsSendableClosure,
						indent: lineIndent,
					)
				}
				let constructionExpression = construction(at: indent)
				// A node a public mock builds for a received dependency is given the value its caller passed, if any.
				let promotedParameterName = publicMock?.promotedParameterNames[node.property]
				// The values of the `@Sendable` autoclosure parameters this node instantiates, bound in its own
				// scope, before the children that receive them.
				let sendableAutoclosureBindings = sendableAutoclosureBindings(
					for: node,
					parameters: sendableAutoclosureParameters,
					indent: "\(indent)\(standardIndent)",
				)

				if node.isInstantiator {
					// For Instantiator nodes, children are generated INSIDE the builder
					// function because they may depend on forwarded properties that are
					// only available as function parameters. This mirrors the production
					// code which builds the entire subtree inside the builder function.
					var childAncestors = ancestorTypes
					childAncestors.insert(nodeTypeKey)
					let loopMemberEmission = loopMembers?.emission(of: node, atPropertyNodeIndex: propertyNodeIndex - 1, functionName: functionName, flatParameterDisambiguationMap: flatParameterDisambiguationMap, lazilyInstantiatedBindingNames: lazilyInstantiatedBindingNames)
					let bindingLines = await generateInstantiatorBinding(
						for: node,
						outerBindingName: outerBindingName,
						functionName: functionName,
						enclosingFunctionNames: builderFunctionNames.enclosingFunctionNames,
						nodePath: nodePath,
						overrideExpression: overrideExpression,
						arguments: arguments,
						sendableAutoclosureBindings: sendableAutoclosureBindings,
						indent: indent,
						ancestorTypes: childAncestors,
						sendableOverrideExtractor: sendableOverrideExtractor,
						flatParameterDisambiguationMap: combinedDisambiguationMap,
						lazilyInstantiatedBindingNames: lazilyInstantiatedBindingNames,
						uncoveredDependencyNames: uncoveredDependencyNames,
						sendableAutoclosureParameters: sendableAutoclosureParameters,
						cycleEdges: cycleEdges,
						overridePathReachable: thisOverrideReachable,
						handWrittenMockDefaultParameters: handWrittenMockDefaultParameters,
						sendableConfigurationTypeNames: sendableConfigurationTypeNames,
						publicMock: publicMock,
						promotedParameterName: promotedParameterName,
						publicMockOverridesIsSendableClosure: publicMockOverridesIsSendableClosure,
						overrideLocalNames: &overrideLocalNames,
						loopMemberEmission: loopMemberEmission,
						bindingNamesPassedByName: bindingNamesPassedByName,
						enclosingBindingNamesPassedByName: enclosingBindingNamesPassedByName,
					)
					if let loop = node.loop {
						appendToLoopUnit(loop, bindingLines)
					} else {
						lines.append(contentsOf: bindingLines.all)
					}
				} else if node.isPropertyCycle {
					// A constant that closes a cycle declares no function: it calls the function of the declaration it
					// repeats with that function's cycle parameters. It reads no override of its own (`isCycleNode`); the
					// function reads the declaration's, so an override applies to every build of the type, re-entries too.
					let closerArguments = mockCycleParameterArguments(
						for: node,
						flatParameterDisambiguationMap: flatParameterDisambiguationMap,
						lazilyInstantiatedBindingNames: lazilyInstantiatedBindingNames,
					).joined(separator: ", ")
					lines.append("\(indent)let \(outerBindingName): \(node.instantiatedTypeSpelledAsDeclared.asSource) = \(functionName)(\(closerArguments))")
				} else if node.requiresFunctionWrapper
					|| hasDisambiguatedReceiver(node, flatParameterDisambiguationMap: combinedDisambiguationMap)
					|| !sendableAutoclosureBindings.isEmpty
					|| node.fillingGenerator != nil
				{
					// Constant node that needs a dedicated Swift scope — either for its
					// own children/defaults/cycle, for aliased deps, to host the
					// `let <label>: <Type> = <disambiguatedName>` binding that aliases a
					// disambiguated flat mock parameter back to its natural label, or to
					// bind the value of a `@Sendable` autoclosure parameter it instantiates. A
					// function scope keeps child bindings from colliding with siblings'
					// child bindings that share the same property label and gives these
					// receiver bindings a place to live.
					let propertyTypeName = node.instantiatedTypeSpelledAsDeclared.asSource
					let innerIndent = "\(indent)\(standardIndent)"
					// The node's own receives have labels of their own, which neither its declarations nor its uncovered
					// dependencies share.
					let uncoveredDependencies = uncoveredInstantiatedDependencies(of: node)
					// The parameters of the builder function, when a cycle closes on it, which hide the bindings of their
					// labels inside it, as an instantiator's do (`generateInstantiatorBinding`).
					let ownCycleParameters = node.cycleParameters
					let ownCycleParameterForms = ownCycleParameters.flatMap(\.providedForms).sorted()
					let functionDisambiguationMap = routingReceives(
						of: uncoveredDependencies,
						toParametersNamed: uncoveredDependencyNames,
						in: removingRenames(
							hiddenByDeclarationsOf: node.children,
							parameters: ownCycleParameterForms,
							from: combinedDisambiguationMap,
						),
					)
					let functionLazilyInstantiatedBindingNames = removingRenames(
						hiddenByDeclarationsOf: node.children,
						parameters: uncoveredDependencies.map(\.property) + ownCycleParameterForms,
						from: lazilyInstantiatedBindingNames,
					)
					let functionParameters = ownCycleParameters.map(\.property)
					let functionArguments = functionParameters.isEmpty ? "" : functionParameters.initializerFunctionParameters(amongTypesDeclaredEscaping: node.typesDeclaredEscaping).map(\.description).joined()
					let callArguments = mockCycleParameterArguments(
						for: node,
						flatParameterDisambiguationMap: flatParameterDisambiguationMap,
						lazilyInstantiatedBindingNames: lazilyInstantiatedBindingNames,
					).joined(separator: ", ")
					let functionDecorator = node.buildsInSendableFunction ? "@Sendable " : ""

					let receiverBindings = emitReceiverBindings(
						for: node.dependencies,
						unavailableProperties: node.unavailableProperties,
						lazilyInstantiatedInstanceProperties: node.lazilyInstantiatedInstanceProperties,
						flatParameterDisambiguationMap: functionDisambiguationMap,
						bindingNamesPassedByName: bindingNamesPassedByName,
						indent: innerIndent,
					)

					// A `@Sendable` function that is not already inside another one – one a cycle closes on from inside a
					// `@Sendable` builder function – starts a new extraction, as an instantiator's does: every
					// `safeDIOverrides` read in its body becomes a local declared before it.
					let startedSendableOverrideExtractor: SendableOverrideExtractor? = if sendableOverrideExtractor == nil, node.buildsInSendableFunction {
						SendableOverrideExtractor(functionName: functionName, names: overrideLocalNames)
					} else {
						nil
					}
					var childAncestors = ancestorTypes
					childAncestors.insert(nodeTypeKey)
					let childBindings = await generateMockBodyBindings(
						items: node.children,
						parentPath: nodePath,
						indent: innerIndent,
						ancestorTypes: childAncestors,
						sendableOverrideExtractor: sendableOverrideExtractor ?? startedSendableOverrideExtractor,
						flatParameterDisambiguationMap: functionDisambiguationMap,
						enclosingFunctionNames: builderFunctionNames.enclosingFunctionNames,
						lazilyInstantiatedBindingNames: functionLazilyInstantiatedBindingNames,
						uncoveredDependencyNames: uncoveredDependencyNames,
						sendableAutoclosureParameters: sendableAutoclosureParameters,
						parentConcreteType: node.concreteType.asSource,
						cycleEdges: cycleEdges,
						overridePathReachable: thisOverrideReachable,
						handWrittenMockDefaultParameters: handWrittenMockDefaultParameters,
						sendableConfigurationTypeNames: sendableConfigurationTypeNames,
						publicMock: publicMock?.beneathRoot,
						enclosingBindingNamesPassedByName: bindingNamesPassedByName,
					)

					let functionConstructionExpression = if let startedSendableOverrideExtractor {
						// The caller read this node's own override and arguments outside any `@Sendable` function; the
						// construction is inside this one, so it reads them into locals too.
						mockConstructionExpression(
							for: node,
							overrideExpression: overrideExpression.map {
								startedSendableOverrideExtractor.extract($0, localNameSuffix: ReservedName.configurationBuilderPropertyName)
							},
							arguments: mockBuilderArguments(
								for: node,
								nodePath: nodePath,
								lazilyInstantiatedBindingNames: argumentLazilyInstantiatedBindingNames,
								uncoveredDependencyNames: uncoveredDependencyNames,
								sendableOverrideExtractor: startedSendableOverrideExtractor,
								overrideReachable: thisOverrideReachable,
								handWrittenMockDefaultParameters: nodeHandWrittenMockDefaultParameters,
								sendableConfigurationTypeNames: sendableConfigurationTypeNames,
								publicMock: publicMock,
								bindingNamesPassedByName: bindingNamesPassedByName,
							),
							overrideReachable: thisOverrideReachable,
							handWrittenMockDefaultParameters: nodeHandWrittenMockDefaultParameters,
							publicMock: publicMock,
							publicMockOverridesIsSendableClosure: publicMockOverridesIsSendableClosure,
							indent: innerIndent,
						)
					} else {
						construction(at: innerIndent)
					}
					if let startedSendableOverrideExtractor {
						overrideLocalNames = startedSendableOverrideExtractor.names
						for extraction in startedSendableOverrideExtractor.extractions {
							lines.append("\(indent)let \(extraction.localName) = \(extraction.expression)")
						}
					}

					// The function's return type gives both branches of the `if`
					// expression a contextual type, so no annotation is needed.
					lines.append("\(indent)\(functionDecorator)func \(functionName)(\(functionArguments)) -> \(propertyTypeName) {")
					// A `@Sendable` function calls the members its places' routes need at its top (`memberCallsInsideBuilderFunction`).
					for valuesBinding in node.memberCallsInsideBuilderFunction {
						lines.append("\(innerIndent)\(valuesBinding.line(bindingNamesPassedByName: enclosingBindingNamesPassedByName, lazilyInstantiatedBindingNames: lazilyInstantiatedBindingNames))")
					}
					await lines.append(contentsOf: callPreamble(of: node, indent: innerIndent))
					lines.append(contentsOf: receiverBindings)
					lines.append(contentsOf: sendableAutoclosureBindings)
					lines.append(contentsOf: childBindings)
					lines.append("\(innerIndent)return \(functionConstructionExpression)")
					lines.append("\(indent)}")
					if let promotedParameterName {
						lines.append("\(indent)let \(outerBindingName): \(propertyTypeName) = \(passing(promotedParameterName, orBuilding: "\(functionName)(\(callArguments))"))")
					} else {
						lines.append("\(indent)let \(outerBindingName): \(propertyTypeName) = \(functionName)(\(callArguments))")
					}
				} else if let promotedParameterName {
					// Both branches give the property's type, which the default construction may not without the annotation.
					lines.append("\(indent)let \(outerBindingName)\(node.overriddenBindingTypeAnnotation) = \(passing(promotedParameterName, orBuilding: constructionExpression))")
				} else {
					// Leaf constant node — flat binding, no scoping needed.
					let typeAnnotation = overrideExpression == nil ? "" : node.overriddenBindingTypeAnnotation
					lines.append("\(indent)let \(outerBindingName)\(typeAnnotation) = \(constructionExpression)")
				}
			}
		}

		emitLoopUnit()
		return lines
	}

	/// Emits a single `let <alias>: <Type> = <fulfillingLabel>` line, resolving
	/// the fulfilling label through `flatParameterDisambiguationMap` when the
	/// fulfiller is a renamed flat mock parameter or a disambiguated sibling.
	/// The line refers to the alias's declaration as the production
	/// dependency-tree output does.
	/// - Parameter holeFunctionName: For a site of a hole held in a wrapper, the name of the function the wrapper is built
	///   around where it differs from `functionName(toBuild:)`.
	private static func emitAliasBinding(
		_ alias: MockAliasNode,
		holeFunctionName: String?,
		flatParameterDisambiguationMap: [String: [TypeDescription: String]],
		lazilyInstantiatedBindingNames: [String: [TypeDescription: String]],
		indent: String,
	) -> String {
		if let holeSite = alias.holeSite {
			return GeneratedCodeText.indentingNonEmptyLines(
				of: buildSiteCode(of: alias.property, at: holeSite, functionName: holeFunctionName, readingInstancesOf: alias.holeSiteLazilyInstantiatedInstanceProperties, lazilyInstantiatedBindingNames: lazilyInstantiatedBindingNames),
				by: indent,
			)
		}
		guard !alias.isBoundToNil else {
			return GeneratedCodeText.indentingNonEmptyLines(of: referencingDeclaration(of: "let \(alias.property.asSource) = nil", by: alias.declarationReference), by: indent)
		}
		let fulfillingLabel = alias.fulfillingLabel
		let fulfillingValue = if alias.fulfillingPropertyIsLazilyInstantiatedInstance {
			// The instance is read from the `LazilyInstantiated` binding, which a label collision may have renamed.
			"\(disambiguatedLazilyInstantiatedBinding(named: fulfillingLabel, withInstanceOfType: alias.fulfillingTypeDescription.unwrapped, disambiguationMap: flatParameterDisambiguationMap)?.name ?? fulfillingLabel).\(Dependency.lazilyInstantiatedInstancePropertyName)"
		} else {
			flatParameterDisambiguationMap[fulfillingLabel]?[alias.fulfillingTypeDescription]
				?? lazilyInstantiatedBindingNames[fulfillingLabel]?[alias.fulfillingTypeDescription]
				?? fulfillingLabel
		}
		return GeneratedCodeText.indentingNonEmptyLines(
			of: referencingDeclaration(
				of: aliasDeclaration(
					of: alias.property,
					fulfilledBy: fulfillingValue,
					ofType: alias.fulfillingTypeDescription,
					erasedToConcreteExistential: alias.erasedToConcreteExistential,
					fulfillingValueMayBeOptional: alias.onlyIfAvailable,
				),
				by: alias.declarationReference,
			),
			by: indent,
		)
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
			      isBoundApart(alias, from: redeclaredNames)
			else { return item }
			var bindingName = "\(alias.property.label)_\(alias.property.typeDescription.simplified.asIdentifier)".spelledAsJoinedIdentifier
			while !takenNames.insert(bindingName).inserted {
				bindingName = "\(bindingName)_".spelledAsJoinedIdentifier
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
				isBoundToNil: alias.isBoundToNil,
				// No site of a hole is renamed: `publicMockFindings` rejects a public mock that would bind one apart
				// (`publicMockHoleSiteBoundApartFinding`), since it would hand its builders two values under the label. An
				// internal mock, and a listed type's, takes the dependency as a parameter under its label and has no site, so
				// it accepts the shape: a deliberate gap.
				loop: alias.loop,
				declaredProperty: alias.declaredProperty ?? alias.property,
			))
		}
		return (renamedItems, bindingNames)
	}

	/// Whether `renamingAliases` binds `alias`, an alias of the mocked type or a site of one of its holes, under a name of
	/// its own, since its label is among `redeclaredNames` (`MockRootTopLevelNames.namesAliasesAreBoundApartFrom`).
	static func isBoundApart(_ alias: MockAliasNode, from redeclaredNames: Set<String>) -> Bool {
		redeclaredNames.contains(alias.property.label)
	}

	/// `disambiguationMap` without the renames that a nested scope's declarations hide: those of the
	/// properties `children` declare – each property node's property and each alias's property – and of
	/// `parameters`, the forwarded properties a builder function is handed.
	///
	/// A receiver of `x: X` or `x: X?` in a scope that declares, or is handed as a parameter, `x: X` resolves
	/// to that declaration by its label, as in production, not to a renamed flat parameter or override of
	/// the same property that an enclosing scope binds, nor to the `LazilyInstantiated` an enclosing mock
	/// wraps around the instance it is passed. Prune the flat parameter and override renames and the
	/// lazily instantiated binding names alike.
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
	/// Beneath a pruned edge, where the node has no `SafeDIOverrides` storage,
	/// a non-dependency argument is the default its `SafeDIMockConfiguration`
	/// declares (see `callSiteArgumentsForPrunedOverride(handWrittenMockDefaultParameters:)`).
	/// When the node's type is in `sendableConfigurationTypeNames`, its struct stores
	/// each non-closure default as a `@Sendable` closure (`generateConfigurationStruct`),
	/// so the argument calls it, wherever it is read from. Every struct stores the value of an
	/// `@autoclosure` parameter as a closure, which the argument calls too.
	private static func resolveBuilderArguments(
		for node: MockParameterNode,
		nodePath: String,
		lazilyInstantiatedBindingNames: [String: [TypeDescription: String]],
		uncoveredDependencyNames: [String: [TypeDescription: String]],
		sendableOverrideExtractor: SendableOverrideExtractor?,
		overrideReachable: Bool,
		handWrittenMockDefaultParameters: [MockParameterNode.DefaultParameter],
		sendableConfigurationTypeNames: Set<String>,
		bindingNamesPassedByName: [String: String],
	) -> [String] {
		// Each label names one dependency: `validateDependencyLabelsAreDistinct` rejects a declaration in a generated tree that repeats one.
		let dependenciesByLabel = Dictionary(grouping: node.dependencies, by: \.property.label).compactMapValues(\.first)
		let relativePath = GeneratedCodeText.overrideRelativePath(of: nodePath)
		let argumentsToSurface = node.surfacedCallSiteArguments(
			overrideReachable: overrideReachable,
			handWrittenMockDefaultParameters: handWrittenMockDefaultParameters,
		)
		let storesDefaultsAsClosures = sendableConfigurationTypeNames.contains(node.concreteType.asSource)
		/// `expression`, called when the struct stores the default of `argument` as a closure: always for an
		/// `@autoclosure` parameter, and for every value that is not a function when the struct is `@Sendable`-typed.
		func readingDefault(_ expression: String, of argument: Initializer.Argument) -> String {
			let typeDescription = argument.typeDescription.strippingEscaping
			return if typeDescription.autoclosureValueType != nil || (storesDefaultsAsClosures && !typeDescription.isClosure) {
				"\(expression)()"
			} else {
				expression
			}
		}
		return argumentsToSurface.map { argument in
			if let holeArgumentValue = node.holeArgumentValuesByLabel[argument.innerLabel] {
				// A builder the node's call of another module's public mock fills.
				holeArgumentValue
			} else if let dependency = dependenciesByLabel[argument.innerLabel] {
				dependencyArgument(
					argument,
					of: dependency,
					for: node,
					lazilyInstantiatedBindingNames: lazilyInstantiatedBindingNames,
					uncoveredDependencyNames: uncoveredDependencyNames,
					bindingNamesPassedByName: bindingNamesPassedByName,
				)
			} else if !overrideReachable {
				// The struct is built afresh, so nothing is read from `SafeDIOverrides`, even inside a `@Sendable` function.
				// `MockParameterNode.readsConfigurationBuiltAfresh(handWrittenMockDefaultParameters:)` tells which nodes reach
				// this branch, so that a type built only beneath a repeated ancestor gets the struct it reads.
				readingDefault("\(node.configurationTypeName)().\(argument.label)", of: argument)
			} else if let sendableOverrideExtractor {
				readingDefault(
					sendableOverrideExtractor.extract(
						"\(nodePath).\(argument.label)",
						localNameSuffix: "\(relativePath)_\(argument.label)",
					),
					of: argument,
				)
			} else {
				readingDefault("\(nodePath).\(argument.label)", of: argument)
			}
		}
	}

	/// The expression a mock passes `node`'s construction for `argument`, the argument of `dependency`.
	/// - Parameter bindingNamesPassedByName: The renamed bindings `node` is passed by name rather than under the labels of
	///   its received dependencies (`receivedBindingNamesPassedByName(to:flatParameterDisambiguationMap:lazilyInstantiatedBindingNames:)`).
	static func dependencyArgument(
		_ argument: Initializer.Argument,
		of dependency: Dependency,
		for node: MockParameterNode,
		lazilyInstantiatedBindingNames: [String: [TypeDescription: String]],
		uncoveredDependencyNames: [String: [TypeDescription: String]],
		bindingNamesPassedByName: [String: String],
	) -> String {
		if node.unavailableProperties.contains(dependency.property) {
			"nil"
		} else if dependency.source.isReceived,
		          node.lazilyInstantiatedInstanceProperties.contains(dependency.property.asUnwrappedProperty)
		{
			// A wrapper a public mock takes in place of the instance may be named apart from its label, which only
			// `lazilyInstantiatedBindingNames` names: a declaration of the label in the tree drops the rename beneath it
			// (`removingRenames`), so the receive reads the closer declaration.
			"\(bindingNamesPassedByName[argument.innerLabel] ?? disambiguatedLazilyInstantiatedBinding(named: argument.innerLabel, withInstanceOfType: dependency.property.typeDescription.unwrapped, disambiguationMap: lazilyInstantiatedBindingNames)?.name ?? argument.innerLabel).\(Dependency.lazilyInstantiatedInstancePropertyName)"
		} else if dependency.source.isReceived,
		          let bindingName = lazilyInstantiatedBindingNames[argument.innerLabel]?[dependency.property.typeDescription]
		{
			// The `LazilyInstantiated` the mock wrapped around the instance it was passed.
			bindingName
		} else if case .instantiated = dependency.source,
		          let parameterName = uncoveredDependencyNames[argument.innerLabel]?[dependency.property.typeDescription]
		{
			// The `mock()` parameter of an uncovered dependency, named apart from a name in scope.
			parameterName
		} else {
			bindingNamesPassedByName[argument.innerLabel] ?? argument.innerLabel
		}
	}

	/// The arguments `node` passes the builder function a lazy cycle closes on, labeled by parameter (see
	/// `CycleParameter`): `nil` for a parameter unavailable where it is passed, or the binding the parameter's label
	/// resolves to there – renamed, by `flatParameterDisambiguationMap` or `lazilyInstantiatedBindingNames`, when the
	/// mock binds it under another name – with its instance where the parameter takes a wrapper's instance by value.
	private static func mockCycleParameterArguments(
		for node: MockParameterNode,
		flatParameterDisambiguationMap: [String: [TypeDescription: String]],
		lazilyInstantiatedBindingNames: [String: [TypeDescription: String]],
	) -> [String] {
		node.cycleParameters.map { parameter in
			let label = parameter.property.label
			let unwrappedProperty = parameter.property.asUnwrappedProperty
			let value: String = if node.cycleParameterArgumentUnavailableProperties.contains(parameter.property) {
				"nil"
			} else if node.callSiteLazilyInstantiatedInstanceProperties.contains(unwrappedProperty) {
				// A deliberate gap: reading the instance here creates it when the function is called, not when a receiver in
				// the function's body first reads it. Production does the same (`cycleParameterArguments`). See "Eager
				// instances at a lazy cycle's calls" in `.claude/rules/cycle-generation.md`.
				"\(disambiguatedLazilyInstantiatedBinding(named: label, withInstanceOfType: unwrappedProperty.typeDescription, disambiguationMap: flatParameterDisambiguationMap)?.name ?? label).\(Dependency.lazilyInstantiatedInstancePropertyName)"
			} else {
				// The `LazilyInstantiated` the mock wrapped around the instance it was passed, or the binding the label was renamed to.
				lazilyInstantiatedBindingNames[label]?[parameter.property.typeDescription] ?? flatParameterDisambiguationMap[label]?[parameter.property.typeDescription] ?? flatParameterDisambiguationMap[label]?[unwrappedProperty.typeDescription] ?? label
			}
			return "\(label.spelledAsArgumentLabel): \(value)"
		}
	}

	/// `lazilyInstantiatedBindingNames` inside the builder function of `node`, an instantiator node: without the renames
	/// its children's declarations, its forwarded properties, the dependencies its type instantiates that the mock cannot
	/// build, and the parameters a lazy cycle closing on the function needs hide.
	private static func builderLazilyInstantiatedBindingNames(
		for node: MockParameterNode,
		from lazilyInstantiatedBindingNames: [String: [TypeDescription: String]],
	) -> [String: [TypeDescription: String]] {
		let ownCycleParameterForms = node.isPropertyCycle ? [] : node.cycleParameters.flatMap(\.providedForms).sorted()
		return removingRenames(
			hiddenByDeclarationsOf: node.children,
			parameters: node.forwardedProperties.sorted() + uncoveredInstantiatedDependencies(of: node).map(\.property) + ownCycleParameterForms,
			from: lazilyInstantiatedBindingNames,
		)
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
	/// override and `arguments` through it. `sendableAutoclosureBindings` are the
	/// node's `sendableAutoclosureBindings(for:parameters:indent:)`, emitted at the
	/// top of the inner builder function. `async` for the reason
	/// `generateMockBodyBindings` is.
	/// The first lines of the builder function of a node that calls another module's public mock and fills some of its
	/// builders: the fills, each a function that builds the hole's property as the module that declares the fulfilling
	/// type builds it, and the line that names the mock's guard. They are declared in the function that makes the call,
	/// as a seam call's are, so that two calls of one mock, or a fill and a binding of the calling mock that share a
	/// name, never share a scope. Empty for every other node.
	private static func callPreamble(of node: MockParameterNode, indent: String) async -> [String] {
		guard let fillingGenerator = node.fillingGenerator, let publicMockCall = node.publicMockCall else { return [] }
		var lines = [String]()
		let fillCode = await fillingGenerator.fillCode(propertiesGeneratedLater: node.fillPropertiesGeneratedLater).joined(separator: "\n")
		for line in fillCode.split(separator: "\n", omittingEmptySubsequences: false) where !fillCode.isEmpty {
			lines.append(line.isEmpty ? "" : "\(indent)\(line)")
		}
		lines.append("\(indent)\(publicMockCall.guardLine(for: node.concreteType))")
		return lines
	}

	/// What a member of a loop of builders among the items of one level of a mock emits beyond what any other instantiator
	/// node emits (see `ReceivedBuilderLoops`).
	struct LoopMemberEmission {
		/// The lines that start the member's builder function: the wrappers of the members of its loop that its tree
		/// receives, made again.
		let rebindingLines: [String]
		/// For a member whose builder function takes parameters a lazy cycle needs, or that closes a cycle on such a
		/// function, the function of no such parameters that every wrapper of the member hands, which passes them what the
		/// level binds: its name and the lines that declare it.
		let receivedFunction: (name: String, lines: [String])?
		/// Whether the level binds the member's wrapper (see `MockParameterNode.isReadOutsideItsLoop`).
		let declaresBinding: Bool
	}

	/// The members of the loops of builders among the items of one level of a mock (see `ReceivedBuilderLoops`).
	struct LoopMemberEmissions {
		/// For each loop, the declaration with which a member of the loop wraps each member again, by the member's property:
		/// the name the declaration binds, the level's name of the member's wrapper, and the declaration, indented as the
		/// body of a builder function declared at the level.
		let declarationsByLoop: [Int: [Property: (bindingName: String, declaration: String)]]
		/// The function of no parameters a lazy cycle needs that every wrapper of each member hands, by the member's index
		/// among the level's property nodes, for a member whose builder function takes such parameters.
		let receivedFunctionNameByNodeIndex: [Int: String]
		/// The indent of the body of a builder function declared at the level.
		let indent: String
		/// The emission of the public mock the level is in, if any.
		let publicMock: PublicMockEmission?

		/// What `node`, the property node at `nodeIndex` among the level's property nodes, emits as a member of a loop,
		/// whose builder function is named `functionName`, or `nil` when it is on no loop.
		func emission(
			of node: MockParameterNode,
			atPropertyNodeIndex nodeIndex: Int,
			functionName: String,
			flatParameterDisambiguationMap: [String: [TypeDescription: String]],
			lazilyInstantiatedBindingNames: [String: [TypeDescription: String]],
		) -> LoopMemberEmission? {
			guard let loop = node.loop else { return nil }
			let declarations = declarationsByLoop[loop, default: [:]]
			let forwardedProperties = node.forwardedProperties.sorted()
			let rebindingLines = node.reboundProperties.compactMap { reboundProperty -> String? in
				if reboundProperty == node.property, !node.isPropertyCycle, !node.cycleParameters.isEmpty, let bindingName = declarations[reboundProperty]?.bindingName {
					// The function's own wrapper is made again with the function's own parameters: where a cycle-closing scope
					// builds the tree again, they are that scope's.
					ScopeGenerator.loopMemberDeclaration(
						of: node,
						bindingName: bindingName,
						handing: functionName,
						forwardedArguments: ScopeGenerator.mockForwardedArguments(of: forwardedProperties) + node.cycleParameters.map { "\($0.property.label.spelledAsArgumentLabel): \($0.property.label)" },
						publicMock: publicMock,
						indent: indent,
					)
				} else {
					declarations[reboundProperty]?.declaration
				}
			}
			var receivedFunction: (name: String, lines: [String])?
			if let receivedFunctionName = receivedFunctionNameByNodeIndex[nodeIndex] {
				var memberLines = [String]()
				let cycleArguments = zip(
					node.cycleParameters,
					ScopeGenerator.mockCycleParameterArguments(for: node, flatParameterDisambiguationMap: flatParameterDisambiguationMap, lazilyInstantiatedBindingNames: lazilyInstantiatedBindingNames),
				).map { parameter, argument in
					// A level declares each label once, so at most one of the two forms is a member.
					let unwrappedProperty = parameter.property.asUnwrappedProperty
					if let member = declarations[unwrappedProperty] ?? declarations[unwrappedProperty.asOptionalProperty] {
						memberLines.append(member.declaration)
						return "\(parameter.property.label.spelledAsArgumentLabel): \(member.bindingName)"
					} else {
						return argument
					}
				}
				let functionParameters = forwardedProperties.isEmpty
					? ""
					: forwardedProperties.initializerFunctionParameters(amongTypesDeclaredEscaping: node.typesDeclaredEscaping).map(\.description).joined()
				let callArguments = (forwardedProperties.map { "\($0.label.spelledAsArgumentLabel): \($0.label)" } + cycleArguments).joined(separator: ", ")
				let functionIndent = String(indent.dropLast(ScopeGenerator.standardIndent.count))
				let decorator = node.buildsInSendableFunction || node.property.propertyType.isSendable ? "@Sendable " : ""
				var lines = ["\(functionIndent)\(decorator)func \(receivedFunctionName)(\(functionParameters)) -> \(node.instantiatedTypeSpelledAsDeclared.asSource) {"]
				lines.append(contentsOf: memberLines)
				lines.append("\(indent)\(memberLines.isEmpty ? "" : "return ")\(functionName)(\(callArguments))")
				lines.append("\(functionIndent)}")
				receivedFunction = (name: receivedFunctionName, lines: lines)
			}
			return LoopMemberEmission(rebindingLines: rebindingLines, receivedFunction: receivedFunction, declaresBinding: node.isReadOutsideItsLoop)
		}
	}

	/// The members of the loops of builders among `items`, the items of one level of a mock, whose property nodes are
	/// `propertyNodes`, each bound under `bindingName` and built by the function `functionName` names (see
	/// `ReceivedBuilderLoops`), or `nil` when no item is on a loop, as at nearly every level. A member whose builder
	/// function takes parameters a lazy cycle needs is wrapped through a function of no such parameters,
	/// `__safeDI_<label>_received`, named apart from every name in scope where it is declared or read, as production names
	/// it (see `namesReceivedFunctionsAvoid`): the level's builder functions, `otherNamesInScope`, and the builder
	/// functions, and their `_received` names, that each member's level declares, where its rebindings read it.
	/// - Parameters:
	///   - otherNamesInScope: The names in scope at the level that are not its property nodes' functions.
	///   - indent: The indent of the body of a builder function declared at the level.
	private static func loopMemberEmissions(
		of items: [MockTreeItem],
		propertyNodes: [MockParameterNode],
		bindingName: (MockParameterNode) -> String,
		functionName: (Int, MockParameterNode, String) -> String,
		otherNamesInScope: () -> Set<String>,
		publicMock: PublicMockEmission?,
		indent: String,
	) -> LoopMemberEmissions? {
		let containsLoop = items.contains { item in
			switch item {
			case let .property(node):
				node.loop != nil
			case let .alias(alias):
				alias.loop != nil
			}
		}
		guard containsLoop else { return nil }
		var namesInScope = otherNamesInScope()
		for (nodeIndex, node) in propertyNodes.enumerated() where !node.isPropertyCycle {
			namesInScope.insert(functionName(nodeIndex, node, bindingName(node)))
		}
		for member in propertyNodes where member.loop != nil {
			let memberLevelNodes = member.children.propertyNodes
			let memberLevelLabelMap = disambiguatePropertyLabels(for: memberLevelNodes)
			for node in memberLevelNodes where !node.isPropertyCycle {
				let memberLevelFunctionName = Self.functionName(toBuildPropertyNamed: disambiguatedLabel(for: node, labelMap: memberLevelLabelMap))
				namesInScope.insert(memberLevelFunctionName)
				namesInScope.insert(ReservedName.receivedBuilderFunctionName(of: memberLevelFunctionName))
			}
		}
		var names = GeneratedNameAllocator(reserving: namesInScope)
		var declarationsByLoop = [Int: [Property: (bindingName: String, declaration: String)]]()
		var receivedFunctionNameByNodeIndex = [Int: String]()
		var memberByProperty = [Property: (node: MockParameterNode, functionName: String)]()
		for (nodeIndex, node) in propertyNodes.enumerated() {
			guard let loop = node.loop else { continue }
			let nodeBindingName = bindingName(node)
			var memberFunctionName = functionName(nodeIndex, node, nodeBindingName)
			if !node.cycleParameters.isEmpty {
				memberFunctionName = names.claim(ReservedName.receivedBuilderFunctionName(of: memberFunctionName))
				receivedFunctionNameByNodeIndex[nodeIndex] = memberFunctionName
			}
			declarationsByLoop[loop, default: [:]][node.property] = (
				bindingName: nodeBindingName,
				declaration: loopMemberDeclaration(
					of: node,
					bindingName: nodeBindingName,
					handing: memberFunctionName,
					forwardedArguments: mockForwardedArguments(of: node.forwardedProperties.sorted()),
					publicMock: publicMock,
					indent: indent,
				),
			)
			memberByProperty[node.property] = (node, memberFunctionName)
		}
		// A rename the level declares of a member is wrapped again under its own label, wrapping the member's function.
		for case let .alias(alias) in items {
			guard let loop = alias.loop,
			      let member = memberByProperty[Property(label: alias.fulfillingLabel, typeDescription: alias.fulfillingTypeDescription)]
			else { continue }
			declarationsByLoop[loop, default: [:]][alias.declaredProperty ?? alias.property] = (
				bindingName: alias.property.label,
				declaration: indent + aliasDeclaration(
					of: alias.property,
					fulfilledBy: mockInstantiatorConstruction(
						of: member.node.typeDescription,
						handing: member.functionName,
						forwardedArguments: mockForwardedArguments(of: member.node.forwardedProperties.sorted()).joined(separator: ", "),
						indent: indent,
					),
					ofType: member.node.typeDescription,
					erasedToConcreteExistential: false,
					fulfillingValueMayBeOptional: false,
				),
			)
		}
		return LoopMemberEmissions(
			declarationsByLoop: declarationsByLoop,
			receivedFunctionNameByNodeIndex: receivedFunctionNameByNodeIndex,
			indent: indent,
			publicMock: publicMock,
		)
	}

	/// The declaration, indented by `indent`, that binds `node`'s wrapper as `bindingName`, handing it the function named
	/// `functionName` called with `forwardedArguments`: in a public mock that takes the wrapper, the value its caller
	/// passed, if any.
	private static func loopMemberDeclaration(
		of node: MockParameterNode,
		bindingName: String,
		handing functionName: String,
		forwardedArguments: [String],
		publicMock: PublicMockEmission?,
		indent: String,
	) -> String {
		let unwrappedType = node.typeDescription.unwrapped
		let binding = unwrappedType.isConstructedByAnnotation ? "\(bindingName): \(unwrappedType.asSource)" : bindingName
		let construction = mockInstantiatorConstruction(
			of: node.typeDescription,
			handing: functionName,
			forwardedArguments: forwardedArguments.joined(separator: ", "),
			indent: indent,
		)
		return if let promotedParameterName = publicMock?.promotedParameterNames[node.property] {
			"\(indent)let \(binding) = \(passing(promotedParameterName, orBuilding: construction))"
		} else {
			"\(indent)let \(binding) = \(construction)"
		}
	}

	/// A wrapper of `typeDescription` that hands the function named `functionName`, called with `forwardedArguments`: the
	/// function itself when it takes no arguments, and otherwise a closure, whose lines after the first are indented by
	/// `indent`, that calls it.
	private static func mockInstantiatorConstruction(
		of typeDescription: TypeDescription,
		handing functionName: String,
		forwardedArguments: String,
		indent: String,
	) -> String {
		let unwrappedTypeDescription = typeDescription.unwrapped.spelledForConstruction
		return if forwardedArguments.isEmpty {
			"\(unwrappedTypeDescription)(\(functionName))"
		} else {
			"""
			\(unwrappedTypeDescription) {
			\(indent)\(standardIndent)\(functionName)(\(forwardedArguments))
			\(indent)}
			"""
		}
	}

	/// The arguments a wrapper's closure passes the builder function of a type whose `@Forwarded` properties are
	/// `forwardedProperties`, in their order, from its argument: the argument itself for one property, and its elements by
	/// label for several.
	private static func mockForwardedArguments(of forwardedProperties: [Property]) -> [String] {
		let forwardedPropertiesHaveLabels = forwardedProperties.count > 1
		return forwardedProperties.map {
			if forwardedPropertiesHaveLabels {
				"\($0.label.spelledAsArgumentLabel): $0.\($0.label)"
			} else {
				"\($0.label.spelledAsArgumentLabel): $0"
			}
		}
	}

	private static func generateInstantiatorBinding(
		for node: MockParameterNode,
		outerBindingName: String,
		functionName: String,
		enclosingFunctionNames: [BuiltDeclaration: String],
		nodePath: String,
		overrideExpression: String?,
		arguments: [String],
		sendableAutoclosureBindings: [String],
		indent: String,
		ancestorTypes: Set<String>,
		sendableOverrideExtractor: SendableOverrideExtractor?,
		flatParameterDisambiguationMap: [String: [TypeDescription: String]],
		lazilyInstantiatedBindingNames: [String: [TypeDescription: String]],
		uncoveredDependencyNames: [String: [TypeDescription: String]],
		sendableAutoclosureParameters: [Property: SendableAutoclosureParameter],
		cycleEdges: Set<CycleEdge>,
		overridePathReachable: Bool,
		handWrittenMockDefaultParameters: [TypeDescription: [MockParameterNode.DefaultParameter]],
		sendableConfigurationTypeNames: Set<String>,
		publicMock: PublicMockEmission? = nil,
		promotedParameterName: String? = nil,
		publicMockOverridesIsSendableClosure: Bool,
		overrideLocalNames: inout GeneratedNameAllocator,
		loopMemberEmission: LoopMemberEmission? = nil,
		bindingNamesPassedByName: [String: String],
		enclosingBindingNamesPassedByName: [String: String],
	) async -> InstantiatorBindingLines {
		let forwardedProperties = node.forwardedProperties.sorted()
		let innerIndent = "\(indent)\(standardIndent)"
		// The parameters of the builder function a lazy cycle closes on, when this node declares it.
		let ownCycleParameters = node.isPropertyCycle ? [] : node.cycleParameters
		let ownCycleParameterForms = ownCycleParameters.flatMap(\.providedForms).sorted()
		// The builder function's parameters and bindings hide the renames of their properties, and so do the dependencies
		// the node's type instantiates that the mock cannot build. The node's own receives have labels of their own.
		let uncoveredDependencies = uncoveredInstantiatedDependencies(of: node)
		let builderDisambiguationMap = routingReceives(
			of: uncoveredDependencies,
			toParametersNamed: uncoveredDependencyNames,
			in: removingRenames(
				hiddenByDeclarationsOf: node.children,
				parameters: forwardedProperties + ownCycleParameterForms,
				from: flatParameterDisambiguationMap,
			),
		)
		let builderLazilyInstantiatedBindingNames = builderLazilyInstantiatedBindingNames(for: node, from: lazilyInstantiatedBindingNames)

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
			bindingNamesPassedByName: bindingNamesPassedByName,
			indent: innerIndent,
		)

		// Build the inner function parameter list (forwarded properties, and the parameters a lazy cycle closing on the
		// function needs).
		let functionParameters = forwardedProperties + ownCycleParameters.map(\.property)
		let functionArguments = if functionParameters.isEmpty {
			""
		} else {
			functionParameters.initializerFunctionParameters(amongTypesDeclaredEscaping: node.typesDeclaredEscaping).map(\.description).joined()
		}

		// Build the forwarded arguments for the Instantiator closure call, followed by the bindings in scope here of the
		// labels the function a lazy cycle closes on takes.
		// A member of a loop of builders whose function takes parameters a lazy cycle needs is wrapped through a function
		// that passes them (see `LoopMemberEmission.receivedFunction`).
		var forwardedArgumentList = mockForwardedArguments(of: forwardedProperties)
		if loopMemberEmission?.receivedFunction == nil {
			forwardedArgumentList.append(contentsOf: mockCycleParameterArguments(
				for: node,
				flatParameterDisambiguationMap: flatParameterDisambiguationMap,
				lazilyInstantiatedBindingNames: lazilyInstantiatedBindingNames,
			))
		}
		let forwardedArguments = forwardedArgumentList.joined(separator: ", ")

		let functionDecorator = if node.buildsInSendableFunction {
			"@Sendable "
		} else {
			""
		}

		var lines = InstantiatorBindingLines()

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
			let startedSendableOverrideExtractor: SendableOverrideExtractor? = if sendableOverrideExtractor == nil, node.buildsInSendableFunction {
				SendableOverrideExtractor(functionName: functionName, names: overrideLocalNames)
			} else {
				nil
			}

			// Generate children's bindings inside the function body.
			// Include this node's type in ancestors so self-referencing
			// cycles (e.g., Instantiator<Self>) are detected.
			var functionAncestors = ancestorTypes
			functionAncestors.insert(node.cycleNodeKey)
			let childBindings = await generateMockBodyBindings(
				items: node.children,
				parentPath: nodePath,
				indent: innerIndent,
				ancestorTypes: functionAncestors,
				sendableOverrideExtractor: sendableOverrideExtractor ?? startedSendableOverrideExtractor,
				flatParameterDisambiguationMap: builderDisambiguationMap,
				enclosingFunctionNames: enclosingFunctionNames,
				lazilyInstantiatedBindingNames: builderLazilyInstantiatedBindingNames,
				uncoveredDependencyNames: uncoveredDependencyNames,
				sendableAutoclosureParameters: sendableAutoclosureParameters,
				parentConcreteType: node.concreteType.asSource,
				cycleEdges: cycleEdges,
				overridePathReachable: overridePathReachable,
				handWrittenMockDefaultParameters: handWrittenMockDefaultParameters,
				sendableConfigurationTypeNames: sendableConfigurationTypeNames,
				publicMock: publicMock?.beneathRoot,
				enclosingBindingNamesPassedByName: bindingNamesPassedByName,
			)

			let nodeHandWrittenMockDefaultParameters = handWrittenMockDefaultParameters[node.concreteType, default: []]
			let functionOverrideExpression: String?
			let functionConstructionArguments: [String]
			if let startedSendableOverrideExtractor {
				// The caller read this node's own override and default arguments
				// from `safeDIOverrides` because it is outside any `@Sendable`
				// function; the construction below is inside this one, so read
				// them into locals too. Override closures are read as optionals;
				// the function body unwraps them and otherwise calls the default
				// construction directly.
				functionConstructionArguments = mockBuilderArguments(
					for: node,
					nodePath: nodePath,
					lazilyInstantiatedBindingNames: ownCycleParameters.isEmpty ? lazilyInstantiatedBindingNames : builderLazilyInstantiatedBindingNames,
					uncoveredDependencyNames: uncoveredDependencyNames,
					sendableOverrideExtractor: startedSendableOverrideExtractor,
					overrideReachable: overridePathReachable,
					handWrittenMockDefaultParameters: nodeHandWrittenMockDefaultParameters,
					sendableConfigurationTypeNames: sendableConfigurationTypeNames,
					publicMock: publicMock,
					bindingNamesPassedByName: bindingNamesPassedByName,
				)
				functionOverrideExpression = overrideExpression.map {
					startedSendableOverrideExtractor.extract($0, localNameSuffix: ReservedName.configurationBuilderPropertyName)
				}
				overrideLocalNames = startedSendableOverrideExtractor.names
				for extraction in startedSendableOverrideExtractor.extractions {
					lines.prelude.append("\(indent)let \(extraction.localName) = \(extraction.expression)")
				}
			} else {
				functionOverrideExpression = overrideExpression
				// The caller read them for the construction inside this function, through the extractor of an enclosing
				// `@Sendable` function if any.
				functionConstructionArguments = arguments
			}

			let functionReturnType = node.instantiatedTypeSpelledAsDeclared.asSource
			// The payloads of the cases on the routes to the places beneath this function, bound before it. A loop's members
			// each bind theirs in a `let`, which every member's function captures, here and in the mock's fills
			// (`SeamHoles.holdsLoopPayloadsInBoxes`), where a seam's tree holds a loop's in one box (`ScopeGenerator.boxedLoops`):
			// a deliberate gap, since a public mock's payloads were never builder structs, so its loops capture what they
			// captured before.
			for valuesBinding in node.valuesBindings {
				lines.prelude.append("\(indent)\(valuesBinding.line(bindingNamesPassedByName: enclosingBindingNamesPassedByName, lazilyInstantiatedBindingNames: lazilyInstantiatedBindingNames))")
			}
			lines.function.append("\(indent)\(functionDecorator)func \(functionName)(\(functionArguments)) -> \(functionReturnType) {")
			// A member of a loop of builders first wraps again the functions of the members its tree receives inside the
			// loop, so each receiver beneath reads a wrapper this call made.
			// A `@Sendable` function calls the members its places' routes need at its top: their results are plain structs it
			// could not capture.
			let memberCallLines = node.memberCallsInsideBuilderFunction.map { valuesBinding in
				"\(innerIndent)\(valuesBinding.line(bindingNamesPassedByName: enclosingBindingNamesPassedByName, lazilyInstantiatedBindingNames: lazilyInstantiatedBindingNames))"
			}
			lines.function.append(contentsOf: memberCallLines)
			let rebindingLines = loopMemberEmission?.rebindingLines ?? []
			lines.function.append(contentsOf: rebindingLines)
			let preamble = await callPreamble(of: node, indent: innerIndent)
			lines.function.append(contentsOf: preamble)
			lines.function.append(contentsOf: receiverBindings)
			lines.function.append(contentsOf: sendableAutoclosureBindings)
			lines.function.append(contentsOf: childBindings)

			// Swift's implicit-return rule only applies when the function
			// body is a single expression. Fills, receiver bindings, autoclosure
			// bindings, and child bindings all add extra statements, so any
			// one forces an explicit `return`. The function's return type
			// gives both branches of an `if` expression a contextual type.
			let returnKeyword = memberCallLines.isEmpty && rebindingLines.isEmpty && preamble.isEmpty && childBindings.isEmpty && receiverBindings.isEmpty && sendableAutoclosureBindings.isEmpty ? "" : "return "
			let builtConstructionExpression = mockConstructionExpression(
				for: node,
				overrideExpression: functionOverrideExpression,
				arguments: functionConstructionArguments,
				overrideReachable: overridePathReachable,
				handWrittenMockDefaultParameters: nodeHandWrittenMockDefaultParameters,
				publicMock: publicMock,
				publicMockOverridesIsSendableClosure: publicMockOverridesIsSendableClosure,
				indent: innerIndent,
			)
			lines.function.append("\(innerIndent)\(returnKeyword)\(builtConstructionExpression)")
			lines.function.append("\(indent)}")
		}
		if let receivedFunction = loopMemberEmission?.receivedFunction {
			lines.function.append(contentsOf: receivedFunction.lines)
		}

		// Emit the Instantiator/ErasedInstantiator construction.
		let unwrappedType = node.typeDescription.unwrapped
		let outerBinding = unwrappedType.isConstructedByAnnotation ? "\(outerBindingName): \(unwrappedType.asSource)" : outerBindingName

		// The builder function now returns the property type directly (including
		// wrapping for erasedToConcreteExistential), so no outer wrapping needed.
		let instantiatorConstruction = mockInstantiatorConstruction(
			of: node.typeDescription,
			handing: loopMemberEmission?.receivedFunction?.name ?? functionName,
			forwardedArguments: forwardedArguments,
			indent: indent,
		)

		if loopMemberEmission?.declaresBinding == false {
			// Only the wrappers its loop makes again hand the member's function.
		} else if let promotedParameterName {
			// A public mock takes a wrapper or an instantiator it builds for a received dependency as itself, so a lazily
			// instantiated one is the caller's own wrapper, built only when the tree reads it, as production holds it.
			lines.binding.append("\(indent)let \(outerBinding) = \(passing(promotedParameterName, orBuilding: instantiatorConstruction))")
		} else {
			lines.binding.append("\(indent)let \(outerBinding) = \(instantiatorConstruction)")
		}

		return lines
	}

	/// The lines `generateInstantiatorBinding` emits for one instantiator node, in the order they are emitted, in three
	/// parts, so that the members of a loop of builders (see `ReceivedBuilderLoops`) are emitted as a unit: every
	/// member's `prelude`, then every member's `function`, then every member's `binding`. A member's function names the
	/// functions of the others, so everything they capture, the prelude's locals among them, must be declared before
	/// any of the unit's wrappers is made; and in a public mock a function that wraps a member again reads the value the
	/// caller passed for it by the name of the member's binding, which a binding declared before the function would hide.
	struct InstantiatorBindingLines {
		/// The locals the function reads that an enclosing `@Sendable` function cannot capture from `safeDIOverrides`, and
		/// the payloads of the cases on the routes to the places beneath the node, bound before the function.
		var prelude = [String]()
		/// The node's builder function, and the function of no parameters a lazy cycle needs that its wrapper hands.
		var function = [String]()
		/// The binding of the node's wrapper.
		var binding = [String]()

		/// Every line, in the order a node on no loop emits them.
		var all: [String] {
			prelude + function + binding
		}
	}

	/// The arguments a mock passes the construction of `node`: those of its construction function in a public mock,
	/// when its type has a configuration (`publicBuilderArguments`), and otherwise `resolveBuilderArguments`'.
	private static func mockBuilderArguments(
		for node: MockParameterNode,
		nodePath: String,
		lazilyInstantiatedBindingNames: [String: [TypeDescription: String]],
		uncoveredDependencyNames: [String: [TypeDescription: String]],
		sendableOverrideExtractor: SendableOverrideExtractor?,
		overrideReachable: Bool,
		handWrittenMockDefaultParameters: [MockParameterNode.DefaultParameter],
		sendableConfigurationTypeNames: Set<String>,
		publicMock: PublicMockEmission?,
		bindingNamesPassedByName: [String: String],
	) -> [String] {
		if let publicMock, node.needsConfigurationStruct {
			publicBuilderArguments(
				for: node,
				nodePath: nodePath,
				lazilyInstantiatedBindingNames: lazilyInstantiatedBindingNames,
				uncoveredDependencyNames: uncoveredDependencyNames,
				sendableOverrideExtractor: sendableOverrideExtractor,
				overrideReachable: overrideReachable,
				emission: publicMock,
				bindingNamesPassedByName: bindingNamesPassedByName,
			)
		} else {
			resolveBuilderArguments(
				for: node,
				nodePath: nodePath,
				lazilyInstantiatedBindingNames: lazilyInstantiatedBindingNames,
				uncoveredDependencyNames: uncoveredDependencyNames,
				sendableOverrideExtractor: sendableOverrideExtractor,
				overrideReachable: overrideReachable,
				handWrittenMockDefaultParameters: handWrittenMockDefaultParameters,
				sendableConfigurationTypeNames: sendableConfigurationTypeNames,
				bindingNamesPassedByName: bindingNamesPassedByName,
			)
		}
	}

	/// The expression that builds `node`: a call of its construction function in a public mock, when its type has a
	/// configuration (`publicConstructionExpression`), and otherwise `MockParameterNode.constructionExpression`.
	/// - Parameters:
	///   - publicMockOverridesIsSendableClosure: For a node that calls another module's public mock, whether the member that
	///     configures it is a `@Sendable` closure: the node is built inside a `@Sendable` builder function, or the struct
	///     that holds the member is read inside one in some mock (`sendableConfigurationTypeNames`).
	///   - indent: The indentation of the line the expression starts on.
	private static func mockConstructionExpression(
		for node: MockParameterNode,
		overrideExpression: String?,
		arguments: [String],
		overrideReachable: Bool,
		handWrittenMockDefaultParameters: [MockParameterNode.DefaultParameter],
		publicMock: PublicMockEmission?,
		publicMockOverridesIsSendableClosure: Bool,
		indent: String,
	) -> String {
		if let publicMockCall = node.publicMockCall, publicMockCall.takesOverrides {
			node.publicMockCallExpression(arguments: arguments, overridesExpression: overrideExpression, overridesIsSendableClosure: publicMockOverridesIsSendableClosure, indent: indent)
		} else if publicMock != nil, node.isBuiltWithPublicConstructionFunction {
			publicConstructionExpression(for: node, overrideExpression: overrideExpression, arguments: arguments)
		} else {
			node.constructionExpression(
				overrideExpression: overrideExpression,
				arguments: arguments,
				overrideReachable: overrideReachable,
				handWrittenMockDefaultParameters: handWrittenMockDefaultParameters,
				indent: indent,
			)
		}
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
}

// MARK: - [MockTreeItem]

extension [ScopeGenerator.MockTreeItem] {
	/// The builders of other modules' public mocks that a call in the tree of these items made in a `@Sendable` builder
	/// function passes up, as the calling tree receives them, which the function captures.
	var passedUpBuildersCapturedBySendableFunctions: Set<Property> {
		var builders = Set<Property>()
		// A stack of its own, since a mock tree can be as deep as the module has types. A subtree that calls no public mock
		// passes nothing up.
		var nodesToVisit = propertyNodes.filter(\.subtreeCallsPublicMock)
		while let node = nodesToVisit.popLast() {
			if node.requiresSendable, let publicMockCall = node.publicMockCall {
				let passedUpLabels = Set(publicMockCall.passedUpBuilders.map(\.label))
				for parameter in publicMockCall.passedParameters {
					if let builder = parameter.builder, passedUpLabels.contains(builder.label) {
						builders.insert(parameter.dependency.property)
					}
				}
			}
			nodesToVisit.append(contentsOf: node.propertyChildren.filter(\.subtreeCallsPublicMock))
		}
		return builders
	}

	/// The generators of the calls of other modules' public mocks in the tree of these items that fill builders
	/// (`ScopeGenerator.MockParameterNode.fillingGenerator`), each with the `propertiesGeneratedLater` its node generates
	/// the fills with (`ScopeGenerator.MockParameterNode.fillPropertiesGeneratedLater`).
	var fillingGenerators: [(generator: ScopeGenerator, propertiesGeneratedLater: Set<Property>)] {
		var fillingGenerators = [(generator: ScopeGenerator, propertiesGeneratedLater: Set<Property>)]()
		// A stack of its own, since a mock tree can be as deep as the module has types. Only a node that calls a public
		// mock fills a builder (`ScopeGenerator.fillsABuilder`).
		var nodesToVisit = propertyNodes.filter(\.subtreeCallsPublicMock)
		while let node = nodesToVisit.popLast() {
			if let fillingGenerator = node.fillingGenerator {
				fillingGenerators.append((fillingGenerator, node.fillPropertiesGeneratedLater))
			}
			nodesToVisit.append(contentsOf: node.propertyChildren.filter(\.subtreeCallsPublicMock))
		}
		return fillingGenerators
	}

	/// The properties the sites of holes among these items bind (see `ScopeGenerator.MockAliasNode.holeSite`).
	var holeSiteProperties: [Property] {
		compactMap { item in
			if case let .alias(alias) = item, alias.holeSite != nil {
				alias.property
			} else {
				nil
			}
		}
	}

	/// Property-typed children only. Aliases are plain `let` bindings and do
	/// not participate in `SafeDIMockConfiguration` / `SafeDIOverrides` or
	/// sibling disambiguation.
	var propertyNodes: [ScopeGenerator.MockParameterNode] {
		compactMap {
			if case let .property(node) = $0 {
				node
			} else {
				nil
			}
		}
	}

	/// The sites of holes among these items that are held in wrappers (see `ScopeGenerator.MockAliasNode.holeSite`), each
	/// of which declares a builder function.
	var holeSitesBuildingWrappers: [ScopeGenerator.MockAliasNode] {
		compactMap {
			if case let .alias(alias) = $0, alias.holeSite != nil, !alias.property.propertyType.isConstant {
				alias
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

// MARK: - Property.PropertyType

extension Property.PropertyType {
	/// Whether the property is an `Instantiator`, `ErasedInstantiator`, or `LazilyInstantiated`, which a
	/// `@Sendable` function cannot capture.
	fileprivate var isNonSendableWrapper: Bool {
		!isConstant && !isSendable
	}
}

extension SeamSignature.Hole.Field {
	/// This field, declaring `property`, a form of its own property, and keeping everything else it holds.
	func withProperty(_ property: Property) -> SeamSignature.Hole.Field {
		SeamSignature.Hole.Field(
			property: property,
			access: access,
			accessCause: accessCause,
			declaringType: declaringType,
			declarationLocation: declarationLocation,
			isReceivedOnlyIfAvailable: isReceivedOnlyIfAvailable,
			parameterTakingType: parameterTakingType,
			deferral: deferral,
			bindsMemo: bindsMemo,
			isSeamParameter: isSeamParameter,
			isBoundByPublicMockRoot: isBoundByPublicMockRoot,
		)
	}

	/// The field as a fill that reads it from its struct binds it: a deferred parameter's binds the memo, its
	/// `LazilyInstantiated` (or `SendableLazilyInstantiated`), under the field's label, so the fill's tree reads its instance
	/// where it reads the value and the value is created when the tree reads it, as inline. The field keeps its own property,
	/// which decides what it satisfies; only the type it is bound as (`boundTypeAsFunctionParameter`) and the spelling of its
	/// reads change (`Scope.fillUnderConstruction`). It stays the seam's parameter (`seamParameterOrigin`), which a place inside
	/// the fill carries on (`SeamBuilderParameters.fields(of:)`).
	var bindingItsMemo: SeamSignature.Hole.Field {
		SeamSignature.Hole.Field(
			property: property,
			access: access,
			accessCause: accessCause,
			declaringType: declaringType,
			declarationLocation: declarationLocation,
			isReceivedOnlyIfAvailable: isReceivedOnlyIfAvailable,
			parameterTakingType: parameterTakingType,
			deferral: deferral,
			bindsMemo: true,
			isSeamParameter: isSeamParameter,
			isBoundByPublicMockRoot: isBoundByPublicMockRoot,
			seamParameterOrigin: seamParameterOrigin,
		)
	}

	/// The field as a fill is handed it where it takes `memo`, the memo of a deferred parameter that a level on a carried route
	/// holds, or one its routes make (`FillDispatcher.memosHanded(toFillOf:labels:readingSendableWrapper:among:)`): a field of that parameter's
	/// form and deferral, which the fill binds as the memo, or by value where its tree reads it inside a `@Sendable` function,
	/// as it binds a passed-up place's (`Scope.fillUnderConstruction`). The field the place carries can be another level's
	/// form of the label, further out, such as the wrapper a type above the deferring seam declares; the memo is the value
	/// the route hands.
	func handedAsMemo(_ memo: ScopeGenerator.FillDispatcher.HandedMemo) -> SeamSignature.Hole.Field {
		SeamSignature.Hole.Field(
			property: memo.property,
			access: access,
			accessCause: accessCause,
			declaringType: declaringType,
			declarationLocation: declarationLocation,
			isReceivedOnlyIfAvailable: isReceivedOnlyIfAvailable,
			parameterTakingType: parameterTakingType,
			deferral: memo.deferral,
			bindsMemo: bindsMemo,
			isSeamParameter: isSeamParameter,
			seamParameterOrigin: isBoundByPublicMockRoot ? nil : seamParameterOrigin,
		)
	}

	/// The field's label in the type a function that is handed it takes it as (`boundTypeAsFunctionParameter`), with no type
	/// declared escaping: what the root dispatcher hands a target that takes the field's memo is found by it
	/// (`ScopeGenerator.FillCallerReads.memoArgumentByMemo`).
	var memoProperty: Property {
		Property(label: property.label, typeDescription: boundTypeAsFunctionParameter(amongTypesDeclaredEscaping: []))
	}

	/// The type a function that is handed the field takes it as: the memo's where the field `bindsMemo`, else the field's own,
	/// as a function parameter.
	func boundTypeAsFunctionParameter(amongTypesDeclaredEscaping typesDeclaredEscaping: Set<TypeDescription>) -> TypeDescription {
		if bindsMemo, let memoType {
			memoType
		} else {
			property.typeDescription.asFunctionParameter(amongTypesDeclaredEscaping: typesDeclaredEscaping)
		}
	}

	/// What code reads the field from its struct under: a deferred parameter's memo where the field `bindsMemo`, else the
	/// field's own name.
	func memberName(bindingMemo: Bool) -> String {
		bindingMemo && isDeferredParameter ? memoName : property.label.spelledAsMemberReference
	}
}

extension SeamCall {
	/// The line before a call of the seam's generated initializer that names the seam's guard enum, so that a call generated
	/// from another signature fails to compile there rather than pass `nil` where the initializer expects a value, with a
	/// comment saying what to do then.
	func guardLine(for concreteType: TypeDescription) -> String {
		"_ = \(concreteType.asSource).\(guardTypeName).self\(comment.lineEnd(for: concreteType))"
	}
}

extension TypeDescription {
	/// This type, or, for a throwing `@autoclosure`, the `@autoclosure` that does not throw and returns the same value: how a
	/// mock takes a default-valued `@autoclosure` it calls where it builds the type (`Initializer.Argument.isLeftToItsDefault`).
	fileprivate var autoclosureTakenWithoutThrowing: TypeDescription {
		guard case let .attributed(.closure(arguments, isAsync, true, _, returnType), specifiers, attributes) = self,
		      attributes.contains("autoclosure")
		else { return self }
		return .attributed(.closure(arguments: arguments, isAsync: isAsync, doesThrow: false, thrownType: nil, returnType: returnType), specifiers: specifiers, attributes: attributes)
	}
}
