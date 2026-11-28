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
	///   - cycleClosingRedeclaredLabels: On entry, the `CycleClosingRedeclaredLabels` of `propertiesToGenerate`, merged in
	///     their order; on return, this scope's, which only its parent reads.
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
		closesCycleOnFillPath: Bool = false,
		builtInlineSeamComment: String?,
		isUnavailableDependency: Bool = false,
		seamCall: SeamCall? = nil,
		publicMockCall: PublicMockCall? = nil,
		callPlaceRequiredAliasFulfillingProperties: Set<Property> = [],
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
		isBuiltByFill: Bool = false,
		fillReturnsWrapperBuilder: Bool = false,
		innerScopesCalledWithForwardedValue: [String] = [],
		fill: (hole: SeamSignature.Hole, key: String, functionName: String, boundLabels: Set<String>, fields: [SeamSignature.Hole.Field], caseHoles: [SeamSignature.Hole], emitsCode: Bool, callerReads: FillCallerReads, labelsHandedAsMemo: Set<String>, plainMemoRoutesOfSendableWrapperReads: [String: [FillDispatcher.PlainMemoRoute]], memoOriginsByLabel: [String: [SeamSignature.Hole.Field.SeamParameterOrigin]], carrierUse: SeamCarrierValues.Use?)? = nil,
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
		fillsStoodFor: [FillStoodFor] = [],
		previousPassBuildsFillOfEveryPlace: Bool = false,
		cycleClosingRedeclaredLabels: inout CycleClosingRedeclaredLabels,
	) {
		var seamAndFillFields = SeamAndFillFields()
		seamAndFillFields.fillsStoodFor = fillsStoodFor
		self.placeHoldingProperties = placeHoldingProperties
		seamAndFillFields.builtInlineSeamComment = builtInlineSeamComment
		seamAndFillFields.isUnavailableDependency = isUnavailableDependency
		seamAndFillFields.namesBoundBySeam = namesBoundBySeam
		self.constructsWithHandWrittenMock = constructsWithHandWrittenMock
		self.closedOnDeclaration = closedOnDeclaration
		self.closesCycleOnFillPath = closesCycleOnFillPath
		self.cycleParameters = cycleParameters
		self.cycleParameterUnavailableProperties = cycleParameterUnavailableProperties
		self.callSiteLazilyInstantiatedInstanceProperties = callSiteLazilyInstantiatedInstanceProperties ?? lazilyInstantiatedInstanceProperties
		seamAndFillFields.publicMockCall = publicMockCall
		seamAndFillFields.mockBuilders = mockBuilders
		seamAndFillFields.holeCallArguments = holeCallArguments
		seamAndFillFields.builderCallArguments = builderCallArguments
		seamAndFillFields.fillDispatchers = fillDispatchers
		seamAndFillFields.fillKey = fill?.key
		seamAndFillFields.fillStructBoundLabels = fill?.boundLabels ?? []
		fillBindsDeferredFieldsFromStruct = fill.map { fill in fill.hole.innerSeamType != nil && fill.fields.contains { $0.isDeferredParameter && fill.boundLabels.contains($0.property.label) } } ?? false
		seamAndFillFields.fillLabelsHandedAsMemo = fill?.labelsHandedAsMemo ?? []
		seamAndFillFields.fillPlainMemoRoutesOfSendableWrapperReads = fill?.plainMemoRoutesOfSendableWrapperReads ?? [:]
		seamAndFillFields.fillMemoOriginsByLabel = fill?.memoOriginsByLabel ?? [:]
		seamAndFillFields.fillFields = fill?.fields ?? []
		seamAndFillFields.fillCarrierUse = fill?.carrierUse
		seamAndFillFields.fillCaseHoles = fill?.caseHoles ?? []
		fillEmitsCode = fill?.emitsCode ?? true
		seamAndFillFields.fillCallerReads = fill?.callerReads
		ownerPropertyStack = []
		ownerConcreteTypeStack = []
		seamAndFillFields.passedUpHoles = passedUpHoles
		seamAndFillFields.valuesBindings = valuesBindings
		seamAndFillFields.memberCallsInsideFunction = memberCallsInsideFunction
		self.isBuiltByFill = isBuiltByFill
		self.fillReturnsWrapperBuilder = fillReturnsWrapperBuilder
		seamAndFillFields.innerScopesCalledWithForwardedValue = innerScopesCalledWithForwardedValue
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
		propertiesToGenerateSlot = DeferredReleaseSlot(propertiesToGenerate)
		seamAndFillFields.fillFieldSelection = fill.flatMap { fill in
			propertiesToGenerate.first.flatMap { child in
				FillFieldSelection(hole: fill.hole, boundLabels: fill.boundLabels, fields: fill.fields, child: child)
			}
		}
		// What the code generated for the call's dispatchers decides, from the fills its children generate.
		let publicMockLevelFunctions = Self.publicMockLevelFunctions(
			publicMockCall: publicMockCall,
			fillDispatchers: fillDispatchers,
			builderCallArguments: builderCallArguments,
			namesTakenByCall: namesTakenByCall,
			enclosingLevelCalls: enclosingLevelCalls,
			children: propertiesToGenerate,
		)
		seamAndFillFields.publicMockLevelFunctions = publicMockLevelFunctions
		seamAndFillFields.publicMockOverrideBuilders = Self.publicMockOverrideBuilders(
			publicMockCall: publicMockCall,
			builderCallArguments: builderCallArguments,
			builtInstantiable: fill == nil ? instantiable : nil,
			publicMockLevelFunctions: publicMockLevelFunctions,
			children: propertiesToGenerate,
		)
		containsBuildSite = propertiesToGenerate.contains(where: \.containsBuildSite)
		fieldsCarriedBySites = Self.fieldsCarriedBySites(
			containsBuildSite: containsBuildSite,
			fill: fill.map { (boundLabels: $0.boundLabels, caseHoles: $0.caseHoles) },
			instantiable: instantiable,
			children: propertiesToGenerate,
		)
		passesUpBuilder = !passedUpHoles.isEmpty || propertiesToGenerate.contains(where: \.passesUpBuilder)
		holdsCallReenteringEnclosingFill = holeCallArguments.contains { $0.enclosingFillKey != nil } || propertiesToGenerate.contains(where: \.holdsCallReenteringEnclosingFill)
		treeHoldsCallOrFill = seamCall != nil || publicMockCall != nil || fill != nil || propertiesToGenerate.contains(where: \.treeHoldsCallOrFill)
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
		treeHoldsSendableFunction = buildsInSendableFunction
			|| property?.propertyType.isSendable == true
			|| fill != nil
			|| seamCall?.parameters.contains { $0.deferral == .deferred(isSendable: true) } == true
			|| propertiesToGenerate.contains(where: \.treeHoldsSendableFunction)
		let fillReferences = Self.fillReferences(
			holeCallArguments: holeCallArguments,
			builderCallArguments: builderCallArguments,
			fillDispatchers: fillDispatchers,
			publicMockLevelFunctions: publicMockLevelFunctions,
			children: propertiesToGenerate,
			buildsInSendableFunction: cycleClosings.buildsInSendableFunction,
		)
		seamAndFillFields.sendableFillKeys = fillReferences.sendableFillKeys
		seamAndFillFields.namedFillKeys = fillReferences.namedFillKeys
		seamAndFillFields.inlinableFillKeys = fillReferences.inlinableFillKeys
		seamAndFillFields.referencedFillNamesByKey = fillReferences.referencedFillNamesByKey
		seamAndFillFields.fillKeysReferencedFromSendableFunction = fillReferences.fillKeysReferencedFromSendableFunction
		seamAndFillFields.publicMockLevelReentries = fillReferences.publicMockLevelReentries
		publicMockLevelReentriesChangedInTree = fillReferences.publicMockLevelReentries != previousPassPublicMockLevelReentries
			|| propertiesToGenerate.contains(where: \.publicMockLevelReentriesChangedInTree)
		let deferredFillLabels = Self.deferredFillLabels(
			children: propertiesToGenerate,
			previousPassFillSendableWrapperReads: previousPassFillSendableWrapperReads,
			previousPassFillLabelsReadOnlyAsPlaceField: previousPassFillLabelsReadOnlyAsPlaceField,
		)
		seamAndFillFields.fillDeferredLabelsHiddenByReenteringCalls = deferredFillLabels.hiddenByReenteringCalls
		seamAndFillFields.fillDeferredLabelsReadInsideSendableFunction = deferredFillLabels.readInsideSendableFunction
		seamAndFillFields.fillSendableWrapperReads = deferredFillLabels.sendableWrapperReads
		seamAndFillFields.fillLabelsReadOnlyAsPlaceField = deferredFillLabels.readOnlyAsPlaceField
		// A place whose fill another place's stands for was never asked what the pass after builds its fill with. Where that
		// could say anything of it – a call inside a fill of this call refers to the call's fills, or the fill that stands for
		// it is built another way on the pass after – the call builds a fill for every place from the pass after on, and never
		// goes back, so the passes end.
		let findsFillOfEveryPlaceNeeded = !previousPassBuildsFillOfEveryPlace && !fillsStoodFor.isEmpty && (
			propertiesToGenerate.contains { $0.fillKey != nil && !$0.referencedFillNamesByKey.isEmpty }
				|| fillsStoodFor.contains { deferredFillLabels.readInsideSendableFunction[$0.standInKey] != nil || deferredFillLabels.hiddenByReenteringCalls[$0.standInKey] != nil }
		)
		seamAndFillFields.buildsFillOfEveryPlace = previousPassBuildsFillOfEveryPlace || findsFillOfEveryPlaceNeeded
		fillStructBoundLabelsChangedInTree = deferredFillLabels.fillStructBoundLabelsChangedInTree || findsFillOfEveryPlaceNeeded
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
			// A call place of the per-type plan requires what the tree it stands for requires, as a seam's call does.
			seamCallRequiredThroughAliasProperties: (seamCall?.requiredThroughAliasProperties ?? []).union(callPlaceRequiredAliasFulfillingProperties),
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
			childrenCycleClosingRedeclaredLabels: cycleClosingRedeclaredLabels,
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
		let holdsCycleClosingScope = isPropertyCycle || propertiesToGenerate.contains(where: \.holdsCycleClosingScope)
		self.holdsCycleClosingScope = holdsCycleClosingScope
		cycleParameterSearchInputs = holdsCycleClosingScope
			? CycleParameterSearchInputs(
				instantiable: instantiable,
				forwardedProperties: forwardedProperties,
				aliasBindingDeclaredProperties: aliasBindingDeclaredProperties,
				receivesPassedNil: receivesPassedNil,
				seamCallRequiredThroughAliasProperties: seamCall?.requiredThroughAliasProperties ?? [],
			)
			: nil
		// A scope that closes a cycle builds nothing, so its children are on no loop. A fill's one child is the property it
		// fills, whose builder function the seam's initializer declares: a receive of that property in the fill's tree is a
		// fill finding (`receivesInstantiatorBuildingSite`), never a loop the fill rebinds.
		let receivedBuilderLoops = isPropertyCycle || fill != nil
			? ReceivedBuilderLoops()
			: Self.receivedBuilderLoops(of: propertiesToGenerate, requiredOnlyIfAvailableAliasProperties: aliasRequirements.requiredOnlyIfAvailableAliasProperties)
		self.receivedBuilderLoops = receivedBuilderLoops
		orderedPropertyToGenerateIndices = Self.orderedPropertyToGenerateIndices(
			of: propertiesToGenerate,
			receivedBuilderLoops: receivedBuilderLoops,
			requiredOnlyIfAvailableAliasProperties: aliasRequirements.requiredOnlyIfAvailableAliasProperties,
			placeHoldingProperties: placeHoldingProperties,
			startingCarriersLast: true,
		)
		receivedBuilderLoopsChangedInTree = receivedBuilderLoops != (previousPassReceivedBuilderLoops ?? ReceivedBuilderLoops())
			|| propertiesToGenerate.contains(where: \.receivedBuilderLoopsChangedInTree)
		// In a seam's own tree, a loop whose members bind two or more payloads or levels holds them in one box, unless a
		// member's function is `@Sendable`, which could not capture the box (see `boxedLoops`).
		let loopBoxes = Self.loopBoxes(
			holdsLoopPayloadsInBoxes: holdsLoopPayloadsInBoxes,
			receivedBuilderLoops: receivedBuilderLoops,
			children: propertiesToGenerate,
		)
		seamAndFillFields.boxedLoops = loopBoxes.boxedLoops
		seamAndFillFields.loopLevelsTypesInTree = loopBoxes.loopLevelsTypesInTree
		seamAndFillFieldsStorage = SeamAndFillFieldsStorage.storing(seamAndFillFields)
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

	/// The fields the build sites in this scope's subtree carry of labels declared above this scope (see
	/// `fieldsCarriedBySites`).
	@inline(never)
	nonisolated private static func fieldsCarriedBySites(
		containsBuildSite: Bool,
		fill: (boundLabels: Set<String>, caseHoles: [SeamSignature.Hole])?,
		instantiable: Instantiable,
		children propertiesToGenerate: [ScopeGenerator],
	) -> Set<Property> {
		guard containsBuildSite else { return [] }
		// A site's field of a label declared here reads this scope's declaration, or the site carries no field of it.
		let labelsDeclaredHere = if let fill {
			fill.boundLabels.union(fill.caseHoles.flatMap(\.uncarriedDeclarations).map(\.property.label))
		} else {
			Set(propertiesToGenerate.compactMap(\.property?.label) + instantiable.dependencies.filter { $0.source == .forwarded }.map(\.property.label))
		}
		return Set(propertiesToGenerate.flatMap(\.fieldsCarriedBySites).filter { !labelsDeclaredHere.contains($0.label) })
	}

	/// The level functions of a call of another module's public mock, from the fills its children generate, or `nil` for any
	/// other scope (see `PublicMockLevelFunctions`).
	@inline(never)
	nonisolated private static func publicMockLevelFunctions(
		publicMockCall: PublicMockCall?,
		fillDispatchers: [FillDispatcher],
		builderCallArguments: [BuilderCallArgument],
		namesTakenByCall: Set<String>,
		enclosingLevelCalls: [String: PublicMockLevelFunctions.EnclosingLevelCall],
		children propertiesToGenerate: [ScopeGenerator],
	) -> PublicMockLevelFunctions? {
		guard publicMockCall != nil, !fillDispatchers.isEmpty else { return nil }
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
					callerReadFormsByLabel[label, default: [:]].merge([field.property: (field, argument.spelled)]) { form, _ in form }
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
		return PublicMockLevelFunctions(
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
	}

	/// The loops among `children` whose levels one box holds, each with its box type's name, and the box types declared
	/// anywhere in this scope's tree (see `boxedLoops`).
	@inline(never)
	nonisolated private static func loopBoxes(
		holdsLoopPayloadsInBoxes: Bool,
		receivedBuilderLoops: ReceivedBuilderLoops,
		children propertiesToGenerate: [ScopeGenerator],
	) -> (boxedLoops: [Int: String], loopLevelsTypesInTree: [String: String]) {
		var boxedLoops = [Int: String]()
		var loopLevelsTypesInTree = [String: String]()
		if holdsLoopPayloadsInBoxes, !receivedBuilderLoops.loopByChildIndex.isEmpty {
			// Each loop's bindings in index order, the order the body generates its members in (`orderedPropertiesToGenerate`).
			var bindingsByLoop = [Int: [SeamHoles.ValuesBinding]]()
			for (index, loop) in receivedBuilderLoops.loopByChildIndex.sorted(by: { $0.key < $1.key }) where !propertiesToGenerate[index].isAlias {
				// A run struct is bound before the box and read only by the bindings the box holds, so the box holds none.
				bindingsByLoop[loop, default: []] += propertiesToGenerate[index].valuesBindings.filter { $0.formsRunAfter == nil }
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
		return (boxedLoops, loopLevelsTypesInTree)
	}

	/// The names this scope's subtree declares `@escaping` (see `typesDeclaredEscaping`).
	@inline(never)
	nonisolated private static func typesDeclaredEscaping(
		instantiable: Instantiable,
		publicMockCall: PublicMockCall?,
		seamCall: SeamCall?,
		children: [ScopeGenerator],
	) -> Set<TypeDescription> {
		var typesDeclaredEscaping = typesDeclaredEscaping(ownedBy: instantiable, publicMockCall: publicMockCall, seamCall: seamCall)
		for child in children where !child.typesDeclaredEscaping.isEmpty {
			typesDeclaredEscaping.formUnion(child.typesDeclaredEscaping)
		}
		return typesDeclaredEscaping
	}

	/// The names a scope of `instantiable` declares `@escaping` itself, without its children's: those its initializers'
	/// parameters declare so, those its aliases name in place of one, and those of the seam or public mock it calls. A call
	/// place of the per-type plan declares the union of these over every scope its tree reaches (`CallPlaceShadow`).
	nonisolated static func typesDeclaredEscaping(
		ownedBy instantiable: Instantiable,
		publicMockCall: PublicMockCall?,
		seamCall: SeamCall?,
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
			let placeFields = fill.fillCaseHoles.flatMap(\.fields)
			for field in fill.fillFields where fill.fillLabelsHandedAsMemo.contains(field.property.label) && FillDispatcher.readsOnlyAsPlaceField(field, placeFields: placeFields, reads: built.reads, carriedBySites: built.fieldsCarriedBySites) {
				fillLabelsReadOnlyAsPlaceField[key, default: []].insert(field.property.label)
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
			let instancePropertyByLabel = FillDispatcher.sendableWrapperReads(ofLabelsHandedAsMemo: fill.fillLabelsHandedAsMemo, labelsReadOnlyAsPlaceField: fillLabelsReadOnlyAsPlaceField[key] ?? [], among: built.receivedProperties)
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
	struct Receives {
		let receivedProperties: Set<Property>
		let requiredReceivedProperties: Set<Property>
		/// The properties the scope's own dependencies receive.
		let ownReceivedProperties: Set<Property>
	}

	/// - Parameter cycleParameters: For a scope that closes a lazy cycle, the parameters of the function it refers to;
	///   empty otherwise.
	@inline(never)
	nonisolated static func receives(
		children: [some CycleParameterSearchNode],
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
			let childRequiredReceivedProperties = child.searchRequiredReceivedProperties
			for property in child.searchReceivedProperties where isReceivedFromAncestors(property, propertiesToDeclare: propertiesToDeclare, forwardedProperties: forwardedProperties) {
				let isRequired = childRequiredReceivedProperties.contains(property)
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
	nonisolated static func aliasRequirements(
		children: [some CycleParameterSearchNode],
		propertiesToDeclare: Set<Property>,
		forwardedProperties: Set<Property>,
		cycleParameters: [CycleParameter],
		seamCallRequiredThroughAliasProperties: Set<Property>,
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
				child.searchRequiredReceivedProperties.contains(property)
					|| child.searchRequiredAliasFulfillingProperties.contains { $0.label == property.label && provides(property, aFormReadBy: $0) }
			}
		}
		var requiredOnlyIfAvailableAliasProperties = Set<Property>()
		var requiredOnlyIfAvailableAliasFulfillingProperties = Set<Property>()
		for case let (aliasProperty?, fulfillingProperty?) in children.lazy.map({ ($0.searchProperty, $0.searchOnlyIfAvailableAliasFulfillingProperty) })
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
		let requiredAliasFulfillingProperties = Set(children.flatMap(\.searchRequiredAliasFulfillingProperties))
			.union(requiredOnlyIfAvailableAliasFulfillingProperties)
			.union(cycleParameters.flatMap(\.requiredAliasFulfillingForms))
			.union(seamCallRequiredThroughAliasProperties)
			.filter { !declaredLabels.contains($0.label) }
		return (requiredOnlyIfAvailableAliasProperties, requiredAliasFulfillingProperties)
	}

	/// - Parameter cycleParameters: For a scope that closes a lazy cycle, the parameters of the function it refers to;
	///   empty otherwise.
	@inline(never)
	nonisolated static func onlyIfAvailableUnwrappedReceivedProperties(
		children: [some CycleParameterSearchNode],
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
			for property in propertyToGenerate.searchOnlyIfAvailableUnwrappedReceivedProperties
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
	struct CycleParameterSearch {
		let cycleClosingRedeclaredLabels: CycleClosingRedeclaredLabels
		let foundCycleParameters: [CycleParameter]
		let unpassableCycleLabelsInTree: [UnpassableCycleLabel]
	}

	@inline(never)
	nonisolated static func cycleParameterSearch(
		instantiable: Instantiable,
		property: Property?,
		declaration: BuiltDeclaration?,
		closedOnDeclaration: BuiltDeclaration?,
		isPropertyCycle: Bool,
		childrenTakePartInCycle: Bool,
		childrenCycleClosingRedeclaredLabels: CycleClosingRedeclaredLabels,
		children: [some CycleParameterSearchNode],
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
		// The children's maps arrive merged, so no child keeps a copy once this scope exists (see
		// `CycleClosingRedeclaredLabels`).
		var cycleClosingRedeclaredLabels = CycleClosingRedeclaredLabels()
		if let closedOnDeclaration {
			cycleClosingRedeclaredLabels.open(closedOn: closedOnDeclaration)
		} else if childrenTakePartInCycle {
			cycleClosingRedeclaredLabels = childrenCycleClosingRedeclaredLabels
		}
		var foundCycleParameters = [CycleParameter]()
		var unpassableCycleLabelsInTree = [UnpassableCycleLabel]()
		// The labels declared between this scope and the scopes that close a cycle on it, where one does. They are declared
		// between every other cycle-closing scope in this subtree and the scope it closes on, too (see below).
		var redeclarationsOfOwnCycle = [String: CycleParameter.Redeclaration]()
		if let property, let declaration, !isPropertyCycle, let redeclarations = cycleClosingRedeclaredLabels.removeRedeclarations(closedOn: declaration) {
			redeclarationsOfOwnCycle = redeclarations
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
		for child in children {
			let childUnpassableCycleLabels = child.searchUnpassableCycleLabelsInTree
			guard !childUnpassableCycleLabels.isEmpty else { continue }
			unpassableCycleLabelsInTree.append(contentsOf: childUnpassableCycleLabels)
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
			// A scope in this subtree that closes a cycle on a scope above this one is built inside this scope's builder
			// function, which the scopes closing a cycle on this scope call again: beneath every declaration between this
			// scope and them. So the type that scope builds again is built beneath those declarations too, whether or not
			// this scope's own tree receives their labels: `W` builds `U`, which builds `W` again and `P`, which declares
			// `l` and builds `U` again, so the `W` that the `U` beneath `P` builds is beneath `P`'s `l`, though no scope on
			// `W` -> `U` -> `W` declares it. Without them `W`'s function took no `l`, `U`'s tree therefore received none, and
			// a receiver in `W`'s tree read the `l` above the first `W` wherever it was built.
			for (label, redeclaration) in redeclarationsOfOwnCycle {
				redeclarations[label] = redeclarations[label].map { $0.preceding(redeclaration) } ?? redeclaration
			}
			cycleClosingRedeclaredLabels.add(redeclarations)
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
		seamAndFillFieldsStorage = nil
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
		orderedPropertyToGenerateIndices = []
		requiredAliasFulfillingProperties = []
		cycleClosedOnDeclarations = []
		isReferencedByCycleClosingScope = false
		closedOnDeclaration = nil
		declaration = nil
		cycleClosedOnDeclarationsReferencedFromSendableFunction = []
		buildsInSendableFunction = false
		treeHoldsSendableFunction = false
		declaresBuilderFunction = false
		childrenTakePartInCycle = false
		holdsCycleClosingScope = false
		cycleParameterSearchInputs = nil
		typesDeclaredEscaping = []
		cycleParameters = []
		cycleParameterUnavailableProperties = []
		callSiteLazilyInstantiatedInstanceProperties = []
		foundCycleParameters = []
		unpassableCycleLabelsInTree = []
		cycleParametersChangedInTree = false
		receivedBuilderLoops = ReceivedBuilderLoops()
		receivedBuilderLoopsChangedInTree = false
		publicMockLevelReentriesChangedInTree = false
		reboundProperties = []
		description = property.asSource
		propertiesToGenerateSlot = DeferredReleaseSlot([])
		propertiesToDeclare = []
		instantiatedDependenciesNotGenerated = []
		self.unavailableOptionalProperties = unavailableOptionalProperties
		lazilyInstantiatedInstanceProperties = []
		self.fulfillingPropertyIsLazilyInstantiatedInstance = fulfillingPropertyIsLazilyInstantiatedInstance
		declaredLazilyInstantiatedInstanceProperty = property.asLazilyInstantiatedInstancePropertyOfDeclaredBinding
		self.property = property
		// An alias constructs nothing.
		ownerPropertyStack = []
		ownerConcreteTypeStack = []
		isBuiltByFill = false
		fillReturnsWrapperBuilder = false
		containsBuildSite = false
		placeHoldingProperties = nil
		fieldsCarriedBySites = []
		passesUpBuilder = false
		holdsCallReenteringEnclosingFill = false
		treeHoldsCallOrFill = false
		closesCycleOnFillPath = false
		fillBindsDeferredFieldsFromStruct = false
		fillEmitsCode = true
		fillStructBoundLabelsChangedInTree = false
		constructsWithHandWrittenMock = false
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
		holdsPlace: Bool = true,
		ownerPropertyStack: [Property],
		ownerConcreteTypeStack: [TypeDescription],
		ownerLazilyInstantiatedInstanceProperties: Set<Property> = [],
		carrierSite: SeamHoles.CarrierSite? = nil,
		siteRouteMembers: [SeamSignature.Hole.RouteStep.Member?] = [],
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
		orderedPropertyToGenerateIndices = []
		requiredAliasFulfillingProperties = []
		cycleClosedOnDeclarations = []
		isReferencedByCycleClosingScope = false
		closedOnDeclaration = nil
		closesCycleOnFillPath = false
		// A site that builds a wrapper declares a builder function, which a cycle-closing scope beneath a sibling must not
		// resolve to. No cycle closes on it: a site has no tree beneath it.
		declaration = holeProperty.propertyType.isConstant ? nil : BuiltDeclaration(property: holeProperty, concreteType: holeProperty.typeDescription.asInstantiatedType)
		cycleClosedOnDeclarationsReferencedFromSendableFunction = []
		buildsInSendableFunction = false
		treeHoldsSendableFunction = false
		declaresBuilderFunction = !holeProperty.propertyType.isConstant
		childrenTakePartInCycle = false
		holdsCycleClosingScope = false
		cycleParameterSearchInputs = nil
		typesDeclaredEscaping = []
		cycleParameters = []
		cycleParameterUnavailableProperties = []
		callSiteLazilyInstantiatedInstanceProperties = ownerLazilyInstantiatedInstanceProperties
		foundCycleParameters = []
		unpassableCycleLabelsInTree = []
		cycleParametersChangedInTree = false
		receivedBuilderLoops = ReceivedBuilderLoops()
		receivedBuilderLoopsChangedInTree = false
		publicMockLevelReentriesChangedInTree = false
		reboundProperties = []
		description = holeProperty.asSource
		propertiesToGenerateSlot = DeferredReleaseSlot([])
		propertiesToDeclare = []
		instantiatedDependenciesNotGenerated = []
		unavailableOptionalProperties = []
		lazilyInstantiatedInstanceProperties = []
		fulfillingPropertyIsLazilyInstantiatedInstance = false
		fulfillingBindingIsOptional = false
		fulfillingExpression = nil
		declaredLazilyInstantiatedInstanceProperty = holeProperty.asLazilyInstantiatedInstanceProperty
		property = holeProperty
		var seamAndFillFields = SeamAndFillFields()
		seamAndFillFields.valuesBindings = carrierSite?.formations ?? []
		seamAndFillFields.siteCarrierUse = carrierSite?.use
		seamAndFillFields.siteRouteMembers = siteRouteMembers
		seamAndFillFieldsStorage = SeamAndFillFieldsStorage.storing(seamAndFillFields)
		isBuiltByFill = false
		fillReturnsWrapperBuilder = false
		containsBuildSite = holdsPlace
		placeHoldingProperties = nil
		fieldsCarriedBySites = Set((site.map(Self.fieldsCarried(by:)) ?? []).map(\.property))
		passesUpBuilder = false
		holdsCallReenteringEnclosingFill = false
		treeHoldsCallOrFill = false
		fillBindsDeferredFieldsFromStruct = false
		fillEmitsCode = true
		fillStructBoundLabelsChangedInTree = false
		constructsWithHandWrittenMock = false
	}

	/// A generator of a seam's tree that the seam's first signature pass built, made again for the seam's emission from
	/// its final signature, `seamRoot`, and `seamHoles`, the `SeamHoles` that signature gives, with `children` in its own
	/// children's place, each already made again: what the generator's construction read of `SeamHoles`, and what it
	/// worked out from its children's, is found again; everything else is the first pass's, which the final signature
	/// leaves alone (see `seam-signature-passes.md`). `sitePath` is the generator's path from the seam's root, its own property
	/// last, and `namesBoundBySeam` what `SeamHoles.namesBoundBySeam` names, joined once for the whole tree.
	///
	/// Every stored property is set here, as `ReseatedField.byStoredProperty` classifies it: the compiler requires each
	/// `let`, and a test requires the classification to name every stored property, `var`s included.
	///
	/// The tree holds no call of a seam or a public mock, no fill and no hole passed up (`confirmingPassFindsNothingNew`),
	/// so none of the fields those set needs to be found again.
	init(
		reseating generator: ScopeGenerator,
		children: [ScopeGenerator],
		sitePath: [Property],
		seamRoot: SeamRoot,
		seamHoles: SeamHoles,
		namesBoundBySeam: Set<String>,
	) {
		var fields = generator.seamAndFillFieldsStorage?.fields ?? SeamAndFillFields()
		var scopeData = generator.scopeData
		var fieldsCarriedBySites = generator.fieldsCarriedBySites
		var builtInstantiable: Instantiable?
		switch generator.scopeData {
		case let .hole(property, erasedToConcreteExistential, _):
			let site = seamHoles.site(at: sitePath)
			let carrierSite = seamHoles.carrierSite(at: sitePath)
			scopeData = .hole(property: property, erasedToConcreteExistential: erasedToConcreteExistential, site: site)
			fields.valuesBindings = carrierSite?.formations ?? []
			fields.siteCarrierUse = carrierSite?.use
			fields.siteRouteMembers = seamHoles.routeMembers(at: sitePath)
			fieldsCarriedBySites = Set((site.map(Self.fieldsCarried(by:)) ?? []).map(\.property))
		case let .root(instantiable, _):
			scopeData = .root(instantiable: instantiable, seamRoot: seamRoot)
			builtInstantiable = instantiable
		case let .property(instantiable, _, _, _, _, _):
			builtInstantiable = instantiable
		case .alias, .fill:
			break
		}
		if let builtInstantiable {
			fields.valuesBindings = seamHoles.valuesBindings(at: sitePath)
			fields.memberCallsInsideFunction = seamHoles.memberCallsInsideFunction(at: sitePath)
			fields.namesBoundBySeam = namesBoundBySeam
			let loopBoxes = Self.loopBoxes(
				holdsLoopPayloadsInBoxes: seamHoles.holdsLoopPayloadsInBoxes,
				receivedBuilderLoops: generator.receivedBuilderLoops,
				children: children,
			)
			fields.boxedLoops = loopBoxes.boxedLoops
			fields.loopLevelsTypesInTree = loopBoxes.loopLevelsTypesInTree
			fieldsCarriedBySites = Self.fieldsCarriedBySites(
				containsBuildSite: generator.containsBuildSite,
				fill: nil,
				instantiable: builtInstantiable,
				children: children,
			)
		}
		self.scopeData = scopeData
		seamAndFillFieldsStorage = SeamAndFillFieldsStorage.storing(fields)
		self.fieldsCarriedBySites = fieldsCarriedBySites
		propertiesToGenerateSlot = DeferredReleaseSlot(children)
		description = generator.description
		receivedProperties = generator.receivedProperties
		receivedOnlyByPublicMockCalls = generator.receivedOnlyByPublicMockCalls
		passedByPublicMockCalls = generator.passedByPublicMockCalls
		ownerPropertyStack = generator.ownerPropertyStack
		ownerConcreteTypeStack = generator.ownerConcreteTypeStack
		closesCycleOnFillPath = generator.closesCycleOnFillPath
		requiredReceivedProperties = generator.requiredReceivedProperties
		unwrappedOptionalRequiredReceivedProperties = generator.unwrappedOptionalRequiredReceivedProperties
		onlyIfAvailableUnwrappedReceivedProperties = generator.onlyIfAvailableUnwrappedReceivedProperties
		onlyIfAvailableAliasFulfillingProperty = generator.onlyIfAvailableAliasFulfillingProperty
		requiredOnlyIfAvailableAliasProperties = generator.requiredOnlyIfAvailableAliasProperties
		requiredAliasFulfillingProperties = generator.requiredAliasFulfillingProperties
		cycleClosedOnDeclarations = generator.cycleClosedOnDeclarations
		isReferencedByCycleClosingScope = generator.isReferencedByCycleClosingScope
		closedOnDeclaration = generator.closedOnDeclaration
		declaration = generator.declaration
		cycleParameters = generator.cycleParameters
		cycleParameterUnavailableProperties = generator.cycleParameterUnavailableProperties
		callSiteLazilyInstantiatedInstanceProperties = generator.callSiteLazilyInstantiatedInstanceProperties
		foundCycleParameters = generator.foundCycleParameters
		unpassableCycleLabelsInTree = generator.unpassableCycleLabelsInTree
		cycleParametersChangedInTree = generator.cycleParametersChangedInTree
		receivedBuilderLoops = generator.receivedBuilderLoops
		orderedPropertyToGenerateIndices = generator.orderedPropertyToGenerateIndices
		receivedBuilderLoopsChangedInTree = generator.receivedBuilderLoopsChangedInTree
		publicMockLevelReentriesChangedInTree = generator.publicMockLevelReentriesChangedInTree
		reboundProperties = generator.reboundProperties
		cycleClosedOnDeclarationsReferencedFromSendableFunction = generator.cycleClosedOnDeclarationsReferencedFromSendableFunction
		buildsInSendableFunction = generator.buildsInSendableFunction
		declaresBuilderFunction = generator.declaresBuilderFunction
		childrenTakePartInCycle = generator.childrenTakePartInCycle
		holdsCycleClosingScope = generator.holdsCycleClosingScope
		cycleParameterSearchInputs = generator.cycleParameterSearchInputs
		typesDeclaredEscaping = generator.typesDeclaredEscaping
		unavailableOptionalProperties = generator.unavailableOptionalProperties
		onlyIfAvailableDependencies = generator.onlyIfAvailableDependencies
		propertiesToDeclare = generator.propertiesToDeclare
		instantiatedDependenciesNotGenerated = generator.instantiatedDependenciesNotGenerated
		passesUpBuilder = generator.passesUpBuilder
		holdsCallReenteringEnclosingFill = generator.holdsCallReenteringEnclosingFill
		fillStructBoundLabelsChangedInTree = generator.fillStructBoundLabelsChangedInTree
		fillBindsDeferredFieldsFromStruct = generator.fillBindsDeferredFieldsFromStruct
		fillEmitsCode = generator.fillEmitsCode
		isBuiltByFill = generator.isBuiltByFill
		fillReturnsWrapperBuilder = generator.fillReturnsWrapperBuilder
		treeHoldsCallOrFill = generator.treeHoldsCallOrFill
		treeHoldsSendableFunction = generator.treeHoldsSendableFunction
		containsBuildSite = generator.containsBuildSite
		placeHoldingProperties = generator.placeHoldingProperties
		lazilyInstantiatedInstanceProperties = generator.lazilyInstantiatedInstanceProperties
		fulfillingPropertyIsLazilyInstantiatedInstance = generator.fulfillingPropertyIsLazilyInstantiatedInstance
		declaredLazilyInstantiatedInstanceProperty = generator.declaredLazilyInstantiatedInstanceProperty
		fulfillingBindingIsOptional = generator.fulfillingBindingIsOptional
		fulfillingExpression = generator.fulfillingExpression
		property = generator.property
		constructsWithHandWrittenMock = generator.constructsWithHandWrittenMock
	}

	/// How `init(reseating:children:sitePath:seamRoot:seamHoles:namesBoundBySeam:)` sets a stored property.
	enum ReseatedField: Sendable {
		/// Taken from the first pass's generator: its construction read nothing of `SeamHoles` into it, and nothing of a
		/// child that is made again.
		case copied
		/// Found again from the final `SeamHoles`, the final seam root, or the children made again.
		case recomputed
		/// A cache code generation fills, empty in every new generator.
		case startsEmpty

		/// Every stored property of a generator, as reflection names it, with how reseating sets it. A stored property
		/// added to `ScopeGenerator` must be added here, which a test checks, and set as this says.
		static let byStoredProperty: [String: ReseatedField] = [
			"description": .copied,
			"receivedProperties": .copied,
			"receivedOnlyByPublicMockCalls": .copied,
			"passedByPublicMockCalls": .copied,
			"ownerPropertyStack": .copied,
			"ownerConcreteTypeStack": .copied,
			"closesCycleOnFillPath": .copied,
			"scopeData": .recomputed,
			"seamAndFillFieldsStorage": .recomputed,
			"requiredReceivedProperties": .copied,
			"unwrappedOptionalRequiredReceivedProperties": .copied,
			"onlyIfAvailableUnwrappedReceivedProperties": .copied,
			"onlyIfAvailableAliasFulfillingProperty": .copied,
			"requiredOnlyIfAvailableAliasProperties": .copied,
			"requiredAliasFulfillingProperties": .copied,
			"cycleClosedOnDeclarations": .copied,
			"isReferencedByCycleClosingScope": .copied,
			"closedOnDeclaration": .copied,
			"declaration": .copied,
			"cycleParameters": .copied,
			"cycleParameterUnavailableProperties": .copied,
			"callSiteLazilyInstantiatedInstanceProperties": .copied,
			"foundCycleParameters": .copied,
			"unpassableCycleLabelsInTree": .copied,
			"cycleParametersChangedInTree": .copied,
			"receivedBuilderLoops": .copied,
			"receivedBuilderLoopsChangedInTree": .copied,
			"publicMockLevelReentriesChangedInTree": .copied,
			"reboundProperties": .copied,
			"cycleClosedOnDeclarationsReferencedFromSendableFunction": .copied,
			"buildsInSendableFunction": .copied,
			"declaresBuilderFunction": .copied,
			"childrenTakePartInCycle": .copied,
			"holdsCycleClosingScope": .copied,
			"cycleParameterSearchInputs": .copied,
			"typesDeclaredEscaping": .copied,
			"unavailableOptionalProperties": .copied,
			"onlyIfAvailableDependencies": .copied,
			"propertiesToGenerateSlot": .recomputed,
			"propertiesToDeclare": .copied,
			"instantiatedDependenciesNotGenerated": .copied,
			"passesUpBuilder": .copied,
			"holdsCallReenteringEnclosingFill": .copied,
			"fillStructBoundLabelsChangedInTree": .copied,
			"fillBindsDeferredFieldsFromStruct": .copied,
			"fillEmitsCode": .copied,
			"isBuiltByFill": .copied,
			"fillReturnsWrapperBuilder": .copied,
			"treeHoldsCallOrFill": .copied,
			"treeHoldsSendableFunction": .copied,
			"containsBuildSite": .copied,
			"placeHoldingProperties": .copied,
			"fieldsCarriedBySites": .recomputed,
			"lazilyInstantiatedInstanceProperties": .copied,
			"fulfillingPropertyIsLazilyInstantiatedInstance": .copied,
			"declaredLazilyInstantiatedInstanceProperty": .copied,
			"fulfillingBindingIsOptional": .copied,
			"fulfillingExpression": .copied,
			"property": .copied,
			"constructsWithHandWrittenMock": .copied,
			"unavailablePropertiesToGenerateCodeTask": .startsEmpty,
			"unavailablePropertiesToGeneratedCode": .startsEmpty,
			"orderedPropertyToGenerateIndices": .copied,
			"$__lazy_storage_$_orderedIndexByUnwrappedProperty": .startsEmpty,
			"$__lazy_storage_$_firstOrderedIndexByProperty": .startsEmpty,
		]

		/// Every field of `SeamAndFillFields`, as reflection names it, with how reseating sets it: those a seam's tree finds
		/// in `SeamHoles` or from its children are found again, and the rest, which only a call, a fill or a mock sets,
		/// are copied. A field added to `SeamAndFillFields` must be added here, which a test checks.
		static let bySeamAndFillField: [String: ReseatedField] = [
			"publicMockCall": .copied,
			"mockBuilders": .copied,
			"fillCallerReads": .copied,
			"publicMockLevelFunctions": .copied,
			"fillKey": .copied,
			"fillFields": .copied,
			"fillCaseHoles": .copied,
			"holeCallArguments": .copied,
			"builderCallArguments": .copied,
			"fillDispatchers": .copied,
			"passedUpHoles": .copied,
			"referencedFillNamesByKey": .copied,
			"publicMockLevelReentries": .copied,
			"fillStructBoundLabels": .copied,
			"fillDeferredLabelsHiddenByReenteringCalls": .copied,
			"fillDeferredLabelsReadInsideSendableFunction": .copied,
			"fillSendableWrapperReads": .copied,
			"fillLabelsReadOnlyAsPlaceField": .copied,
			"fillLabelsHandedAsMemo": .copied,
			"fillPlainMemoRoutesOfSendableWrapperReads": .copied,
			"fillMemoOriginsByLabel": .copied,
			"fillKeysReferencedFromSendableFunction": .copied,
			"sendableFillKeys": .copied,
			"inlinableFillKeys": .copied,
			"namedFillKeys": .copied,
			"valuesBindings": .recomputed,
			"memberCallsInsideFunction": .recomputed,
			"innerScopesCalledWithForwardedValue": .copied,
			"namesBoundBySeam": .recomputed,
			"boxedLoops": .recomputed,
			"loopLevelsTypesInTree": .recomputed,
			"builtInlineSeamComment": .copied,
			"isUnavailableDependency": .copied,
			"publicMockOverrideBuilders": .copied,
			"fillFieldSelection": .copied,
			"siteCarrierUse": .recomputed,
			"siteRouteMembers": .recomputed,
			"fillCarrierUse": .copied,
			"fillsStoodFor": .copied,
			"buildsFillOfEveryPlace": .copied,
		]
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
		carrierUse: SeamCarrierValues.Use? = nil,
		child: ScopeGenerator,
		cycleClosingRedeclaredLabels: inout CycleClosingRedeclaredLabels,
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
			propertiesToDeclare: Self.fieldForms(of: fields, boundLabels: boundLabels).union(Self.propertiesBeingBuilt(byFillOf: hole)),
			// A fill builds only `child`, so no dependency of its own is one a mock is passed instead.
			instantiatedDependenciesNotGenerated: [],
			unavailableOptionalProperties: callerReads.unavailableProperties,
			lazilyInstantiatedInstanceProperties: [],
			forwardedLazilyInstantiatedInstanceProperties: [],
			erasedToConcreteExistential: false,
			isPropertyCycle: false,
			builtInlineSeamComment: nil,
			fillReturnsWrapperBuilder: returnsWrapperBuilder,
			fill: (hole, key, functionName, boundLabels, fields, caseHoles, emitsCode, callerReads, labelsHandedAsMemo, plainMemoRoutesOfSendableWrapperReads, memoOriginsByLabel, carrierUse),
			cycleClosingRedeclaredLabels: &cycleClosingRedeclaredLabels,
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
		var argumentByLabel = [String: ArgumentSource]()
		/// What the root dispatcher hands of each label the fill takes as a `SendableLazilyInstantiated` memo some route hands
		/// it (`Scope.Fill.labelsHandedAsMemo`), by the memo the fill takes (`SeamSignature.Hole.Field.memoProperty`): the
		/// caller's declaration of that wrapper, or one made of the caller's value, so the fill's tree reads the caller's own
		/// wrapper where it reads the wrapper, as inline.
		var memoArgumentByMemo = [Property: ArgumentSource]()
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

	/// The property a fill of `hole` builds, with its instance, where it is no instantiator: the type that owns the place
	/// declares it, so a receive of it in the fill's tree is not received from the scopes enclosing the call. The fill's
	/// tree finds it still being built and passes a receive only if available `nil`, as the same types built inline do,
	/// and a required one is the cycle validation reports; a tree that received it from the caller's scope would hand a
	/// seam a parameter, and a mock an override, that nothing reads. An instantiator is left out: a receive of one is
	/// `receivesInstantiatorBuildingSite`.
	static func propertiesBeingBuilt(byFillOf hole: SeamSignature.Hole) -> Set<Property> {
		guard !isBuilder(hole.property) else { return [] }
		var properties: Set<Property> = [hole.property]
		if let instanceProperty = hole.property.asLazilyInstantiatedInstanceProperty {
			properties.insert(instanceProperty)
		}
		return properties
	}

	/// What a fill of `hole` that a call passes binds from the site's scope struct, and of that what hides the fill's
	/// reads from the caller's scope, as the walk of what the call receives reads it.
	struct FillStructBindings: Sendable {
		/// The forms of the fields the fill binds from the struct, and the property it builds.
		let bound: Set<Property>
		/// `bound` but for the fields of a label a level of an inner seam's enum holds on some route to the place and not
		/// on another, which the fill reads of the caller's scope on that other route
		/// (`InnerScopeReaders.labelsSomeInnerRouteLacks(of:)`).
		let hiddenFromCaller: Set<Property>
	}

	/// What a fill of `hole` binds from the site's scope struct (`FillStructBindings`). A public mock takes no deferred
	/// parameter, so its fill binds every field. A seam's fill reads a field bound from a deferred parameter of the
	/// caller's scope, but for a place a seam passes up from a seam it calls, whose deferred fields hold the memo of what
	/// that call passed, which the fill binds from the struct (`fillUnderConstruction`). So does a fill some route hands
	/// such a memo through the levels on a carried route, by each label of `handedMemoByLabel`
	/// (`FillDispatcher.memosHanded(toFills:ofPublicMockCall:labelsReadOnlyAsPlaceField:readingSendableWrapper:among:)`):
	/// its field is then that memo's, whose forms it binds in place of the place's field of the label, so a read of the
	/// place's field that the memo does not provide is the caller's, as the tree's fill reads it.
	static func structBindings(ofFillOf hole: SeamSignature.Hole, passedByPublicMockCall: Bool, innerScopeReaders: InnerScopeReaders?, handedMemoByLabel: [String: FillDispatcher.HandedMemo] = [:]) -> FillStructBindings {
		let labelsSomeInnerRouteLacks = innerScopeReaders?.labelsSomeInnerRouteLacks(of: hole) ?? []
		let readsDeferredFieldsFromStruct = passedByPublicMockCall || hole.innerSeamType != nil
		let fields = hole.fields.map { field in
			handedMemoByLabel[field.property.label].map { field.handedAsMemo($0) } ?? field
		}
		let boundLabels = Set(fields.filter { readsDeferredFieldsFromStruct || !$0.isDeferredParameter || handedMemoByLabel[$0.property.label] != nil }.map(\.property.label))
		let beingBuilt = propertiesBeingBuilt(byFillOf: hole)
		return FillStructBindings(
			bound: fieldForms(of: fields, boundLabels: boundLabels).union(beingBuilt),
			hiddenFromCaller: fieldForms(of: fields, boundLabels: boundLabels.subtracting(labelsSomeInnerRouteLacks)).union(beingBuilt),
		)
	}

	/// The properties a fill declares that binds those of `fields` labeled in `boundLabels`: the property of each field of
	/// the site's scope struct it binds and, for a lazily instantiated field, the instance a receive reads by value.
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
		init(label: String, value: String, enclosingFill: EnclosingFill? = nil, isSendable: Bool = false, builderStruct: PublicMockBuilderStruct? = nil, overrideHanding: OverrideHanding = .none, passedUpStruct: PassedUpStruct? = nil, builtCall: BuiltCall? = nil) {
			self.label = label
			self.value = value
			self.passedUpStruct = passedUpStruct
			self.builtCall = builtCall
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
		/// Where a seam's call passes the builder's places up, the struct `value` calls a member of, which the type key records
		/// as the call's read; `nil` for every other argument.
		let passedUpStruct: PassedUpStruct?

		/// The builder or level struct a seam's call passing places up calls its member on, by the name the caller's tree binds
		/// it under and its type there, and the member read: of the call's own case.
		struct PassedUpStruct: Sendable {
			let name: String
			let type: TypeDescription
			let caseName: String
			let member: PassedOnMember
		}

		/// Where a seam's call fills the builder's places and declares the dispatchers that fill them, the call of the root
		/// level's dispatcher `value` writes; `nil` for every other argument, and for a call that re-enters an enclosing call's.
		let builtCall: BuiltCall?

		/// The call of the dispatcher of a builder's root level a seam's call passes the builder, handed the struct the case of
		/// the caller's own enum for the call returns, for each struct of a level its fills take.
		struct BuiltCall: Sendable {
			let dispatcherKey: String
			let dispatcherName: String
			let carriedStructs: [CarriedStruct]

			/// A struct the dispatcher is handed: under the label its fills take it by, of its type, bound as `name`.
			struct CarriedStruct: Sendable {
				let upName: String
				let type: TypeDescription
				let name: String
			}

			/// The call, as the argument's value.
			var spelled: String {
				"\(dispatcherName)(\(carriedStructs.map { "\($0.upName.spelledAsArgumentLabel): \($0.name)" }.joined(separator: ", ")))"
			}
		}
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
			/// Whether the case's level is a carrier's `let` child (`SeamSignature.ScopeEnum.Case.isLetChildOfCarrier`), which the
			/// caller's carrier is formed with, not a closure that forms it.
			var isLetChild = false
			/// How a member of a seam's carrier takes the case's values (`SeamCarrierValues`): the struct of the run they end,
			/// then each value after it; `nil` where the case's values travel positionally or as a payload struct.
			var carrierUse: SeamCarrierValues.Use?

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

		/// A fill of a seam call whose code is emitted, as `memosHanded(toFills:ofPublicMockCall:labelsReadOnlyAsPlaceField:readingSendableWrapper:among:)`
		/// reads it: its key, the place it fills, and the fields it takes (`ScopeGenerator.caseFields(of:)` for a case nested
		/// by type, else the place's own).
		struct EmittedFill {
			let key: String
			let hole: SeamSignature.Hole
			let fields: [SeamSignature.Hole.Field]
		}

		/// The memo each fill of `fills` takes of each label some route of `dispatchers` hands it as a memo
		/// (`memosHanded(toFillOf:labels:readingSendableWrapper:among:)`), by the fill's key: only of a seam's call whose
		/// dispatchers hold a level on a carried route that carries a deferred parameter's field, a field of the fill's that
		/// is not a deferred parameter's itself, its case's payload does not carry, and its tree does not read only as the
		/// place's own field (`labelsReadOnlyAsPlaceField`, which the pass before finds: `readsOnlyAsPlaceField(_:placeFields:reads:carriedBySites:)`).
		/// A public mock's caller hands values. Empty for nearly every call.
		///
		/// One rule for the tree, which builds each fill with the memos it takes (`Scope`), and for the per-type facts, which
		/// hide along a fill edge what the fill binds (`TypeFactsGraph`). Which labels are handed and in which form reads the
		/// dispatchers' keys and cases alone, never their names. `readingSendableWrapper` decides only a memo's deferral, never
		/// which labels are handed nor the memo's property.
		static func memosHanded(
			toFills fills: [EmittedFill],
			ofPublicMockCall isPublicMockCall: Bool,
			labelsReadOnlyAsPlaceField: [String: Set<String>],
			readingSendableWrapper: [String: [String: Property]],
			among dispatchers: [FillDispatcher],
		) -> [String: HandedMemos] {
			guard !isPublicMockCall, dispatchers.contains(where: { dispatcher in
				dispatcher.cases.contains { $0.carriesDeferredFields && $0.values?.contains(where: \.isDeferredParameter) == true }
			}) else { return [:] }
			var handedMemosByKey = [String: HandedMemos]()
			for fill in fills {
				let payloadLabels = Set(fill.hole.enumPlace?.values.map(\.property.label) ?? [])
				let readOnlyAsPlaceField = labelsReadOnlyAsPlaceField[fill.key] ?? []
				handedMemosByKey[fill.key] = memosHanded(
					toFillOf: fill.key,
					labels: Set(fill.fields.filter { !$0.isDeferredParameter && !payloadLabels.contains($0.property.label) && !readOnlyAsPlaceField.contains($0.property.label) }.map(\.property.label)),
					readingSendableWrapper: readingSendableWrapper[fill.key] ?? [:],
					among: dispatchers,
				)
			}
			return handedMemosByKey
		}

		/// The `SendableLazilyInstantiated` a fill's tree, which receives `receivedProperties`, reads of each label among
		/// `labelsHandedAsMemo` (the labels some route hands it a memo of) but those it reads only as the place's own field
		/// (`labelsReadOnlyAsPlaceField`), by that wrapper's instance property: the `readingSendableWrapper` of
		/// `memosHanded(toFills:ofPublicMockCall:labelsReadOnlyAsPlaceField:readingSendableWrapper:among:)`. The optional
		/// wrapper only if available is left out (`ScopeGenerator.fillSendableWrapperReads` says why); of two wrappers of one
		/// label, the one that sorts first. One rule for the tree, which finds these reads on the pass before, and the
		/// per-type facts, which find them in the fill target's received fold.
		static func sendableWrapperReads(ofLabelsHandedAsMemo labelsHandedAsMemo: Set<String>, labelsReadOnlyAsPlaceField: Set<String>, among receivedProperties: Set<Property>) -> [String: Property] {
			var instancePropertyByLabel = [String: Property]()
			for property in receivedProperties.sorted() where labelsHandedAsMemo.contains(property.label) && !labelsReadOnlyAsPlaceField.contains(property.label) && property.propertyType == .sendableLazilyInstantiated && !property.typeDescription.isOptional && instancePropertyByLabel[property.label] == nil {
				instancePropertyByLabel[property.label] = property.asLazilyInstantiatedInstanceProperty
			}
			return instancePropertyByLabel
		}

		/// Whether a fill that takes `field`, a memo some route hands it, reads its label only as the place's own field of it,
		/// the wrapper a type further out declares: its tree, which reads what `reads` says, reads neither the memo's value
		/// nor its memo, no site inside it carries the field (`carriedBySites`), and it reads the field of the label the
		/// first of `placeFields` that has one is. Such a fill takes that field on the next pass
		/// (`ScopeGenerator.fillLabelsReadOnlyAsPlaceField`). One rule for the tree and the per-type facts.
		static func readsOnlyAsPlaceField(_ field: SeamSignature.Hole.Field, placeFields: [SeamSignature.Hole.Field], reads: (Property) -> Bool, carriedBySites: Set<Property>) -> Bool {
			guard !reads(field.property), !carriedBySites.contains(field.property), let placeField = placeFields.first(where: { $0.property.label == field.property.label }) else { return false }
			return reads(placeField.property)
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
		/// own places (`CalledBuilders.routesReachOnly(_:by:)`). A caller fills every place of a hole type of a call or
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
			let holesBySite = calledBuilders.holeBySite
			let builtTypeByHoleType = calledBuilders.holes.builtTypeByHoleType
			let calledSeamTypes = Set(calledBuilders.builders.map(\.enumKey.seamType))
			let filledSiteNumbers = calledBuilders.siteNumbers(of: filledSites)
			/// The root enum whose routes from the enum of `key` a dispatcher for `family` serves: none, so every site the enum
			/// reaches counts, where the call is not of a public mock or the dispatcher serves both families.
			func routeRootKey(of key: SeamSignature.ScopeEnum.Key, family: Bool?) -> SeamSignature.ScopeEnum.Key? {
				guard decidesPerRoute, let family else { return nil }
				return rootKey(ofFamily: family, holeType: key.holeType)
			}
			/// Whether the routes of `family`'s root enum reach a filled site from the enum of `key`.
			func reachesFilledSite(from key: SeamSignature.ScopeEnum.Key, onRoutesOf family: Bool?) -> Bool {
				calledBuilders.reaches(anyOf: filledSiteNumbers, from: key, onRoutesOf: routeRootKey(of: key, family: family))
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
					guard reachesFilledSite(from: key, onRoutesOf: family),
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
				!calledBuilders.reachesOnly(filledSiteNumbers, from: key, onRoutesOf: routeRootKey(of: key, family: family))
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
						let target = dispatcherInstance(of: innerKey)
						var dispatcherCase = Case(name: enumCase.name, hasForwardedValue: false, target: nil, values: enumCase.values?.fields, labelsBoundLater: enumCase.values?.labelsBoundLater ?? [])
						dispatcherCase.isLetChild = enumCase.isLetChildOfCarrier(inSendableEnum: scopeEnum.key.isSendable) && ReservedName.seamCarrier(ofEnum: scopeEnum.type) != nil
						if case .fill = enumCase.kind {
							dispatcherCase.isFillCase = true
							dispatcherCase.carriedInnerKey = SeamSignature.ScopeEnum.carriedInnerKey(of: enumCase)
						}
						guard reachesFilledSite(from: innerKey, onRoutesOf: family) else { return dispatcherCase }
						let targetKey = target.dispatcherKey
						return Case(
							name: dispatcherCase.name,
							hasForwardedValue: false,
							target: Case.Target(name: dispatcherNames[targetKey] ?? "", key: targetKey, takesPassUp: takesPassUp(innerKey, onRoutesOf: target.family), reusedCarriedInnerScopes: enclosingCarriedInnerScopes[targetKey] ?? []),
							values: dispatcherCase.values,
							isFillCase: dispatcherCase.isFillCase,
							carriedInnerKey: dispatcherCase.carriedInnerKey,
							labelsBoundLater: dispatcherCase.labelsBoundLater,
							isLetChild: dispatcherCase.isLetChild,
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
					// The most explicit of the places' spellings, as the called seam's builder spells it (`builtTypeByHoleType`).
					returnType: builtTypeByHoleType[key.holeType] ?? key.holeType.builtType,
					isSendableFamily: key.isSendable,
					takesPassUp: takesPassUp(key, onRoutesOf: family),
					cases: cases.map { dispatcherCase in
						var dispatcherCase = dispatcherCase
						dispatcherCase.carriesDeferredFields = carriesDeferredFields
						dispatcherCase.carrierUse = calledBuilders.carrierUse(ofEnum: scopeEnum, count: dispatcherCase.values?.count ?? 0)
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
					return generic.map { ReservedName.levelType(ofEnum: fillLevelEnum.type, built: $0) }
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
							dispatcherCase.isLetChild = enumCase.isLetChildOfCarrier(inSendableEnum: scopeEnum.key.isSendable) && ReservedName.seamCarrier(ofEnum: scopeEnum.type) != nil
							dispatcherCase.carrierUse = calledBuilders.carrierUse(ofEnum: scopeEnum, count: enumCase.values?.fields.count ?? 0)
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

		/// The type a level's struct is generic over on a carried route, given `returnType`, what the level's function returns
		/// its struct over: `carriedType`, the caller's struct of the fill's own level, in place of the built type, inside the
		/// structs of the fills' levels a deeper seam's level returns its struct over.
		static func carried(_ carriedType: TypeDescription, through returnType: TypeDescription) -> TypeDescription {
			switch returnType {
			case let .nested(name, parentType, generics) where ReservedName.namesLevelType(name) && generics.count == 1:
				.nested(name: name, parentType: parentType, generics: [carried(carriedType, through: generics[0])])
			// A level a route carries is always spelled qualified: a carrier by its seam, which another module fills, and a
			// builder struct by its enum.
			case .void, .simple, .nested, .composition, .optional, .implicitlyUnwrappedOptional, .some, .any, .metatype, .attributed, .array, .dictionary, .tuple, .closure, .variadic, .unknown:
				carriedType
			}
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

	// MARK: CustomStringConvertible

	let description: String

	// MARK: Internal

	/// Properties that we require in order to satisfy our (and our children's) dependencies.
	/// Used both to order child generation (dependencies before dependents) and by mock
	/// generation to surface dependencies the tree does not itself provide.
	let receivedProperties: Set<Property>
	/// The properties among `receivedProperties` that only leaves calling another module's public mock receive, each
	/// only if available (see `Scope.publicMockCall`): a mock takes a parameter or override only for those a call passes
	/// (`receivedOnlyByPublicMockCallsLeftOut`).
	let receivedOnlyByPublicMockCalls: Set<Property>
	/// The properties among `receivedOnlyByPublicMockCalls` that some call passes, since the tier it reaches takes them.
	let passedByPublicMockCalls: Set<Property>

	/// The generators of this scope's children, in declaration order, for a walk of a seam's tree that reads what
	/// its generators found. A generator the construction memo shares is a child of each place that reuses it, so a walk
	/// that keys by a generator's identity reads one subtree at every such place (see `construction-memo.md`).
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
	/// Whether this scope, in a fill's tree, closes a cycle on a declaration of the filled seam's path (`closedOnDeclaration`).
	/// `false` for every other scope, a closer on a declaration inside the fill's own tree among them, and for a closer
	/// inside a fill nested in that fill, whose stack is its own. Where on the path the declaration lies is the place's to
	/// say (`SeamSignature.Hole.fillPathDeclarationsBeneath(_:)`): places of one case can share this fill
	/// (`FillStoodFor`), and each has the declaration at its own depth.
	let closesCycleOnFillPath: Bool

	/// Whether this generator's tree reads `field`, a field of a scope struct, as its fill binds it: it receives the
	/// field, its optional form, or its instance.
	nonisolated func reads(_ field: Property) -> Bool {
		Self.reads(field, among: receivedProperties)
	}

	/// Whether a tree that receives `receivedProperties` reads `field` as a fill binds it (see `reads(_:)`).
	nonisolated static func reads(_ field: Property, among receivedProperties: Set<Property>) -> Bool {
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

	/// The receives a type's own `dependencies` make from above its builder function, in declaration order, each with the
	/// dependency that makes it: a received property, and the property an alias binds against where the type does not
	/// declare it. An alias of a property its own type declares reads that declaration, also where a cycle-closing scope
	/// calls the type's builder function, which binds its own: it receives nothing.
	nonisolated static func receivesFromAbove(ofOwnDependencies dependencies: [Dependency]) -> [(property: Property, dependency: Dependency)] {
		var receives = [(property: Property, dependency: Dependency)]()
		// Read only for a type with an alias, which few are.
		var ownDeclaredProperties: Set<Property>?
		for dependency in dependencies {
			switch dependency.source {
			case .received:
				receives.append((dependency.property, dependency))
			case let .aliased(fulfillingProperty, _, onlyIfAvailable):
				let declaredProperties = ownDeclaredProperties ?? propertiesDeclared(byOwnDependencies: dependencies)
				ownDeclaredProperties = declaredProperties
				guard !declaresFulfillingProperty(
					of: fulfillingProperty,
					onlyIfAvailable: onlyIfAvailable,
					declaredProperties: declaredProperties,
					forwardedProperties: [],
				) else { continue }
				receives.append((fulfillingProperty, dependency))
			case .instantiated, .forwarded:
				continue
			}
		}
		return receives
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

	/// The plan of this scope's code as the root of what is generated, with nothing generated before it, which
	/// the caller spells once.
	func generatePlan(
		codeGeneration: CodeGeneration = .dependencyTree,
	) async throws -> GeneratedCode {
		try await generateCode(
			codeGeneration: codeGeneration,
			unavailableProperties: rootUnavailableProperties,
			propertiesGeneratedLater: [],
			builderFunctionNames: BuilderFunctionNames(),
			leadingWhitespace: "",
			// The root of what is generated is inside no fill an internal mock declares.
			fillPlaceBindings: .none,
		)
	}

	/// The places of this scope's body, its children's code in the order it builds them, as a root's body holds them: what
	/// the type key lays out of a body of the per-type plan (`TypeKeyBody.statements(ofPlan:)`).
	func generateChildPlans() async throws -> [GeneratedCode] {
		try await generateProperties(
			propertiesGeneratedLater: [],
			enclosingFunctionNames: BuilderFunctionNames().enclosingFunctionNames,
			leadingMemberWhitespace: "        ",
			fillPlaceBindings: .none,
		)
	}

	/// The extension a root of the dependency tree declares around `statements`, the body the type key laid out; nothing
	/// for a root without dependencies.
	static func rootCode(of instantiable: Instantiable, writing statements: [GeneratedCode]) throws -> GeneratedCode {
		try rootInitializer(of: instantiable)?.spelled(writing: BuilderFunctionGraph(body: statements.map(Statement.verbatim))) ?? .empty
	}

	/// This scope's unavailable properties as the root of what is generated, with nothing generated before it.
	private var rootUnavailableProperties: Set<Property> {
		unavailableProperties(
			isGeneratedBefore: { _ in false },
			propertiesGeneratedLater: [],
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
		}
		if leadingWhitespace.isEmpty {
			return generatedCode
		} else {
			// The level holds its scope's code, which the cache shares, and indents it where the tree is spelled.
			return .indented(generatedCode, by: leadingWhitespace)
		}
	}

	/// The code tasks the generators of this scope's tree still hold (see `HeldCodeTasks`). Once the tree's code is
	/// generated, each is a finished task.
	/// The tree is walked with a stack, since it can be as deep as the module has types. A generator a construction memo
	/// shares between places is reached once for each place, so its tasks count once for each.
	func codeTasksHeldInTree() async -> Int {
		var generators = [self]
		var heldTaskCount = 0
		while let generator = generators.popLast() {
			heldTaskCount += await generator.unavailablePropertiesToGenerateCodeTask.count
			generators += generator.children
		}
		return heldTaskCount
	}

	func generateDOT() async -> String {
		Self.drawnTree(of: self)
	}

	/// The DOT lines of the tree `root` roots, one line per edge of each place, in the order of a depth-first walk of
	/// what each place draws: `generateDOT()`'s text. Walked on an explicit stack, since a tree is as deep as the module
	/// has types.
	nonisolated static func drawnTree(of root: ScopeGenerator) -> String {
		var lines = [String]()
		var generators = [root]
		while let generator = generators.popLast() {
			let drawing = generator.dotDrawing
			lines.append(contentsOf: drawing.lines)
			generators.append(contentsOf: drawing.drawn.reversed().compactMap(\.generator))
		}
		return lines.joined(separator: "\n")
	}

	/// What one place draws of its own in the DOT graph: an edge to each node it draws, in order, then to each property
	/// it forwards, sorted, and the generator that draws each drawn node's own edges, if any.
	struct DOTDrawing {
		/// The place's own node.
		let node: String
		let drawn: [(node: String, generator: ScopeGenerator?)]
		/// The nodes of the properties the place forwards, sorted.
		let forwarded: [String]

		var lines: [String] {
			var lines = [String]()
			for drawnNode in drawn {
				lines.append("    \(node) -- \(drawnNode.node)")
			}
			for forwardedNode in forwarded {
				lines.append("    \(node) -- \(forwardedNode)")
			}
			return lines
		}
	}

	/// What this place draws of its own (`DOTDrawing`). A fill is drawn as the property it fills, which its child builds,
	/// so the seam call's edge leads to that property's own edges rather than to an edge from the property to itself.
	nonisolated var dotDrawing: DOTDrawing {
		if case .fill = scopeData, let child = propertiesToGenerate.first {
			return child.dotDrawing
		} else {
			let orderedPropertiesToGenerate = Array(orderedPropertiesToGenerate)
			// A place whose fill another place's stands for (`FillStoodFor`) is drawn where its own fill would be, among
			// the call's fills in the order the call met their places, with the tree of the fill that stands for it: the
			// tree its own fill would build. So the drawing does not depend on which fills the call built.
			var fillsByKey = [String: ScopeGenerator]()
			if !fillsStoodFor.isEmpty {
				for child in orderedPropertiesToGenerate {
					if let fillKey = child.fillKey {
						fillsByKey[fillKey] = child
					}
				}
			}
			// The fills count in the order the call built them, which `FillStoodFor.builtFillCountBefore` counts in. The fill
			// of a place stood for would hold no place (`Scope.nextFill()`), so it would be drawn among the fills that start
			// with their siblings, before the first of them built after it and before every fill that starts last
			// (`startsAsCarrier(_:)`).
			var builtFillIndexByKey = [String: Int]()
			if !fillsStoodFor.isEmpty {
				for child in propertiesToGenerate {
					if let fillKey = child.fillKey {
						builtFillIndexByKey[fillKey] = builtFillIndexByKey.count
					}
				}
			}
			var drawn = [(node: String, generator: ScopeGenerator?)]()
			var fillsStoodForToDraw = fillsStoodFor[...]
			for orderedPropertyToGenerate in orderedPropertiesToGenerate {
				if let builtFillIndex = orderedPropertyToGenerate.fillKey.flatMap({ builtFillIndexByKey[$0] }) {
					while let fillStoodFor = fillsStoodForToDraw.first, startsAsCarrier(orderedPropertyToGenerate) || fillStoodFor.builtFillCountBefore <= builtFillIndex {
						fillsStoodForToDraw.removeFirst()
						drawn.append(("\"\(fillStoodFor.hole.property.asSource)\"", fillsByKey[fillStoodFor.standInKey]))
					}
				}
				drawn.append((orderedPropertyToGenerate.scopeData.asDOTNode, orderedPropertyToGenerate))
			}
			for fillStoodFor in fillsStoodForToDraw {
				drawn.append(("\"\(fillStoodFor.hole.property.asSource)\"", fillsByKey[fillStoodFor.standInKey]))
			}
			return DOTDrawing(
				node: scopeData.asDOTNode,
				drawn: drawn,
				forwarded: scopeData.forwardedProperties.sorted().map { "\"\($0.asSource)\"" },
			)
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

	/// Whether a `@Sendable` builder function in this body of a root's per-type plan may capture an `Instantiator`,
	/// `ErasedInstantiator`, or `LazilyInstantiated` declared outside it: the walk of
	/// `nonSendableWrapperCaptures(ofTreeRootedAt:)` over the body's tree, each label the body reads from above declared,
	/// outside every `@Sendable` function of the body, as each of `answers` binds it. It may find a capture the plan's
	/// code does not make, where a `@Sendable` function reads a parameter of its own: the root then keeps its tree per
	/// path, whose walk judges it.
	///
	/// - Parameters:
	///   - instantiable: The type the body builds.
	///   - answers: The declarations that answer the labels the body reads from above.
	func mayCaptureNonSendableWrapper(asBodyOf instantiable: Instantiable, answeredBy answers: [NearestDeclaration]) async -> Bool {
		var declarationsByLabel = [String: [VisibleDeclaration]]()
		for answer in answers {
			for (form, declaredProperty) in answer.bindings.sorted(by: { $0.key < $1.key }) {
				declarationsByLabel[form.label, default: []].append(VisibleDeclaration(
					property: declaredProperty,
					instanceProperty: form == declaredProperty ? nil : form,
					declaringType: nil,
					declarationLocation: nil,
					sendableBuilderDepth: 0,
				))
			}
		}
		return await !nonSendableWrapperCaptures(
			of: instantiable,
			unavailableProperties: unavailableProperties(
				isGeneratedBefore: { _ in false },
				propertiesGeneratedLater: [],
			),
			propertiesGeneratedLater: [],
			declarationsByLabel: declarationsByLabel,
			enclosingSendableBuilders: [],
			chain: [],
		).isEmpty
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
		// Only a call of a seam tier that omits a parameter reports, and only a scope that closes a lazy cycle records a
		// call that judges a read elsewhere, so the walk enters no subtree that holds neither, and no tree that holds no
		// such call: its visits record nothing.
		// Several places of the tree can share one generator (see `ConstructionMemo`), so entered at every place a tree of
		// screens that each open three screens of the next layer was walked once per path.
		let generatorsLeadingToOmissions = Self.generatorsLeadingToSeamTierOmissions(inTreeRootedAt: self)
		guard generatorsLeadingToOmissions.contains(ObjectIdentifier(self)) else { return [] }
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
			visitNumber: 0,
			referenceLocation: { instantiable.declarationLocation },
			isOwnFile: isOwnFile,
			generatorsLeadingToOmissions: generatorsLeadingToOmissions,
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

	/// - Parameters:
	///   - enclosingCycleFunctions: The builder functions enclosing this scope that lazy cycles close on and that take
	///     parameters (see `CycleParameter`), by the declaration each builds.
	///   - generatorsLeadingToOmissions: The generators of the tree whose subtree holds a seam call that omits a
	///     parameter or a scope that closes a lazy cycle (`generatorsLeadingToSeamTierOmissions(inTreeRootedAt:)`).
	private func seamTierOmissions(
		of instantiable: Instantiable,
		propertiesGeneratedLater: Set<Property>,
		declarationsByLabel: [String: [VisibleDeclaration]],
		enclosingCycleFunctions: [BuiltDeclaration: Int],
		visitNumber: Int,
		referenceLocation: @escaping @Sendable () -> Dependency.DeclarationLocation?,
		isOwnFile: @escaping @Sendable (String) -> Bool,
		generatorsLeadingToOmissions: Set<ObjectIdentifier>,
	) async -> OmissionFindings<SeamTierOmission> {
		GenerationWork.record(1, by: .findingSeamTierOmissions)
		let declaringType = instantiable.concreteInstantiable
		var declarationLocationByProperty = [Property: Dependency.DeclarationLocation?]()
		for dependency in instantiable.dependencies where !dependency.source.isReceived {
			declarationLocationByProperty[dependency.property] = dependency.declarationLocation
		}
		// A child's construction is referred to by this type's dependency that builds it when this type is declared in
		// one of the module's own files, and otherwise where this type's construction is. Found only for an omission:
		// spelling the file of every type the walk passes cost a root that calls many seams more than the walk did.
		func childReferenceLocation(of property: Property?) -> @Sendable () -> Dependency.DeclarationLocation? {
			{ [declarationLocationByProperty] in
				guard let property, instantiable.sourceFilePath.map(isOwnFile) ?? false else { return referenceLocation() }
				return declarationLocationByProperty[property].flatMap(\.self) ?? referenceLocation()
			}
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

		var findings = OmissionFindings<SeamTierOmission>(nextVisitNumber: visitNumber + 1)
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
					let referenceLocation = childReferenceLocation(of: child.generator.property)()
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
			} else if generatorsLeadingToOmissions.contains(ObjectIdentifier(child.generator)) {
				// This scope calls the child's builder function, which, when a lazy cycle closes on it and it takes parameters,
				// it passes them as each cycle-closing scope does. The function's body reads its parameters, which hide every
				// declaration of their labels where it is called, as generation's do.
				// The function is told apart by the walk's visit of the child, never by its generator, which several places of the
				// tree can share (see `ConstructionMemo`): each place's calls are of a function of its own. A child the walk
				// does not enter takes no number: its function's parameters are read only in its body, which holds no call
				// that omits one.
				let function = findings.nextVisitNumber
				findings.recordCalls(by: child, of: function, among: childDeclarationsByLabel)
				await findings.append(contentsOf: child.generator.seamTierOmissions(
					of: childInstantiable,
					propertiesGeneratedLater: child.generator.bodyPropertiesGeneratedLater(child.propertiesGeneratedLater),
					declarationsByLabel: child.generator.bodyDeclarations(function: function, enclosing: childDeclarationsByLabel),
					enclosingCycleFunctions: child.generator.bodyEnclosingCycleFunctions(function: function, enclosing: enclosingCycleFunctions),
					visitNumber: function,
					referenceLocation: childReferenceLocation(of: child.generator.property),
					isOwnFile: isOwnFile,
					generatorsLeadingToOmissions: generatorsLeadingToOmissions,
				))
			}
		}
		return findings
	}

	/// The generators of the tree `root` roots whose subtree holds a call of a seam tier that omits a parameter, or one no
	/// tier takes, or a scope that closes a lazy cycle: the scopes `seamTierOmissions` enters. Empty where the tree holds no
	/// such call, since a scope that closes a lazy cycle only records calls, which judge the reads of an omitting call
	/// alone: a tree without one reports nothing, and a lazy cycle in it would have the walk enter every path to it again.
	/// Each generator is visited once, from the leaves up; the set dies with the walk.
	private static func generatorsLeadingToSeamTierOmissions(inTreeRootedAt root: ScopeGenerator) -> Set<ObjectIdentifier> {
		var leadingToOmissions = Set<ObjectIdentifier>()
		var holdsCallOmittingParameter = false
		var visitedGenerators = Set<ObjectIdentifier>()
		var generatorsToVisit = [(generator: root, childrenAreVisited: false)]
		while let (visited, childrenAreVisited) = generatorsToVisit.popLast() {
			guard childrenAreVisited else {
				guard visitedGenerators.insert(ObjectIdentifier(visited)).inserted else { continue }
				generatorsToVisit.append((visited, true))
				for child in visited.children where !visitedGenerators.contains(ObjectIdentifier(child)) {
					generatorsToVisit.append((child, false))
				}
				continue
			}
			let (closesCycle, callOmitsParameter) = if case let .property(_, _, _, _, isPropertyCycle, seamCall) = visited.scopeData {
				(isPropertyCycle, seamCall.map { !($0.omittedParameters.isEmpty && $0.noTierParameters.isEmpty) } ?? false)
			} else {
				(false, false)
			}
			holdsCallOmittingParameter = holdsCallOmittingParameter || callOmitsParameter
			if closesCycle || callOmitsParameter || visited.children.contains(where: { leadingToOmissions.contains(ObjectIdentifier($0)) }) {
				leadingToOmissions.insert(ObjectIdentifier(visited))
			}
		}
		guard holdsCallOmittingParameter else { return [] }
		return leadingToOmissions
	}

	/// The value each receive in the tree rooted at this scope, a root of the dependency tree, is handed in each place the
	/// tree builds its type, as generated code resolves its label: the nearest declaration of the label where the receive's
	/// type is constructed, in the order the tree's code is generated, or `nil` where generation passes `nil`
	/// (`unavailableProperties`). Where that declaration is a parameter of a builder function a lazy cycle closes on, the
	/// value is the one each call of the function passes (see `OmissionFindings`). Also returns the concrete type of each
	/// scope the tree constructs, in the order the walk meets them. `query graph` runs it only for trees built around
	/// received dependencies nothing provides, which the fold that replaced it does not read yet, and otherwise only the
	/// fold's oracle runs it (`TypeFactsReceivedValueSuppliesObservation`), since it enters every path of the tree.
	///
	/// A receive `unfulfilledReceives` holds is one the tree was built around although nothing provides it in some place
	/// (`DependencyTreeGenerator.unfulfilledReceiveLocations`). Where nothing provides it, it is handed nothing, and an
	/// absent declaration of its property is in scope for the scopes its type builds, after every declaration of its
	/// label: no receive that reads a declaration reads another for it, and a receive that would find none reads the
	/// absent one, which is reported as the receive that stands for it.
	func receivedValueSupplies(
		ofTreeRootedAt instantiable: Instantiable,
		unfulfilledReceives: UnfulfilledReceives,
	) async -> (supplies: [ReceivedValueSupply], constructedTypes: [TypeDescription])? {
		let findings = await receivedValueSupplies(
			of: instantiable,
			unavailableProperties: [],
			propertiesGeneratedLater: [],
			declarationsByLabel: [:],
			receivableProperties: [],
			unfulfilledReceives: unfulfilledReceives,
			enclosingCycleFunctions: [:],
			visitNumber: 0,
		)
		guard findings.isJudged else { return nil }
		return (findings.judged(), findings.constructedTypes)
	}

	/// The received dependencies and aliases a tree was built around although nothing provides them.
	struct UnfulfilledReceives: Sendable {
		/// Where each is declared.
		let locations: Set<Dependency.DeclarationLocation>
		/// The label each receives: a received dependency's own, an alias's fulfilling property's.
		let labels: Set<String>

		func contains(_ dependency: Dependency) -> Bool {
			dependency.declarationLocation.map(locations.contains) == true
		}
	}

	/// - Parameters:
	///   - unavailableProperties: This scope's `unavailableProperties`, as `generateCode` takes them.
	///   - declarationsByLabel: The declarations each label names where this scope's type is constructed.
	///   - enclosingCycleFunctions: The builder functions enclosing this scope that lazy cycles close on and that take
	///     parameters (see `CycleParameter`), by the declaration each builds.
	///   - receivableProperties: Of the labels `unfulfilledReceives` receive, the properties validation finds receivable
	///     where this scope's type is constructed (`insertProperties`): what the scopes above declare and receive.
	///   - visitNumber: The number the walk gives this visit, which names the builder function this scope's body is.
	private func receivedValueSupplies(
		of instantiable: Instantiable,
		unavailableProperties: Set<Property>,
		propertiesGeneratedLater: Set<Property>,
		declarationsByLabel: [String: [VisibleDeclaration]],
		receivableProperties: Set<Property>,
		unfulfilledReceives: UnfulfilledReceives,
		enclosingCycleFunctions: [BuiltDeclaration: Int],
		visitNumber: Int,
	) async -> ReceivedValueSupplyFindings {
		let declaringType = instantiable.concreteInstantiable
		var findings = ReceivedValueSupplyFindings(nextVisitNumber: visitNumber + 1, constructedType: declaringType)
		/// Records what the receive of `receivedProperty` under `label` reads among `declarationsByLabel`, or `nil`, with
		/// its reason, when generation passes it `nil`, or nothing, when `isReportedUnfulfilled` and nothing provides it here.
		/// - Returns: Whether the receive is handed a value here.
		func recordSupply(
			of receivedProperty: Property,
			label: String,
			isRequired: Bool,
			isReportedUnfulfilled: Bool,
			among declarationsByLabel: [String: [VisibleDeclaration]],
			isPassedNil: Bool,
		) -> SupplyOutcome {
			let unwrappedProperty = receivedProperty.asUnwrappedProperty
			func supply(_ value: ReceivedValueSupply.Value) -> ReceivedValueSupply {
				ReceivedValueSupply(receivingType: declaringType, label: label, value: value)
			}
			let declarations = declarationsByLabel[receivedProperty.label, default: []]
			// Beneath a receive nothing provides, a required receive reads the declaration of exactly the property it
			// requires, the absent one included, as validation judges it. Generation hands a receive the nearest
			// declaration that provides any form of it, which in a valid tree is that one.
			let exactProvider = isRequired && declarations.contains(where: \.isAbsent) ? declarations.first(where: { $0.declares(receivedProperty) }) : nil
			let provider = exactProvider ?? declarations.first(where: { $0.provides(unwrappedProperty) })
			// A parameter of a builder function a lazy cycle closes on hands a receive what each call of the function
			// passes. Validation's test of where the function is declared does not judge that for a receive nothing
			// provides, and an absent declaration beside the parameter is no declaration the calls know of: the walk
			// reports no supply of such trees.
			guard provider?.cycleFunction == nil || !(isReportedUnfulfilled || declarations.contains(where: \.isAbsent)) else {
				findings.leaveUnjudged()
				return .unfulfilled
			}
			// Validation finds a receive unfulfillable exactly where the property it requires is not receivable.
			guard !isReportedUnfulfilled || receivableProperties.contains(receivedProperty) else {
				findings.append(supply(.unfulfilled(nil)))
				return .unfulfilled
			}
			if let provider, provider.isAbsent, let absentDeclaringType = provider.declaringType {
				// Generation, which knows of no absent declaration, passes the receive `nil` or names nothing for it.
				findings.append(supply(.unfulfilled(ReceivedValueSupply.Supplier(declaringType: absentDeclaringType, label: provider.property.label))))
				return .handedValue
			}
			let passedNil = supply(.passedNil(.noProvidingDeclaration))
			guard !isPassedNil, let provider else {
				// Generation also finds a receive unavailable whose nearest declaration provides no form it reads.
				findings.append(provider == nil ? passedNil : passedNil.passingNil(because: .providerNotYetBuilt))
				return .passedNil
			}
			findings.append(reading: unwrappedProperty, from: provider, passedNothing: passedNil) { provider in
				// Every provider a supply is judged at is a declaration of a type of the tree: a parameter of a builder
				// function a lazy cycle closes on, whose declaring type is `nil`, is judged at the calls of the function.
				ReceivedValueSupply(
					receivingType: declaringType,
					label: label,
					value: provider.declaringType.map { .declaration(ReceivedValueSupply.Supplier(declaringType: $0, label: provider.property.label)) } ?? .passedNil(.noProvidingDeclaration),
				)
			}
			return .handedValue
		}
		func visibleDeclaration(of property: Property, instanceProperty: Property?, isAbsent: Bool = false) -> VisibleDeclaration {
			VisibleDeclaration(
				property: property,
				instanceProperty: instanceProperty,
				declaringType: declaringType,
				declarationLocation: nil,
				sendableBuilderDepth: 0,
				isAbsent: isAbsent,
			)
		}
		// The type is constructed in its builder function, which binds its parameters and what it rebinds before anything
		// in it reads them.
		let ownUnavailableProperties = bodyUnavailableProperties(unavailableProperties)
		var childReceivableProperties = receivableProperties
		var absentDeclarations = [VisibleDeclaration]()
		for dependency in instantiable.dependencies where dependency.source.isReceived {
			let outcome = recordSupply(
				of: dependency.property,
				label: dependency.property.label,
				isRequired: dependency.source == .received(onlyIfAvailable: false),
				isReportedUnfulfilled: unfulfilledReceives.contains(dependency),
				among: declarationsByLabel,
				isPassedNil: ownUnavailableProperties.contains(dependency.property),
			)
			guard unfulfilledReceives.labels.contains(dependency.property.label) else { continue }
			switch outcome {
			case .unfulfilled:
				// As every declaration that provides a lazily instantiated property does, the absent one provides its instance.
				absentDeclarations.append(visibleDeclaration(
					of: dependency.property,
					instanceProperty: dependency.property.asLazilyInstantiatedInstancePropertyOfDeclaredBinding,
					isAbsent: true,
				))
				childReceivableProperties.insert(dependency.property)
			case .handedValue:
				childReceivableProperties.insert(dependency.property)
			case .passedNil:
				break
			}
		}

		var scopeDeclarationsByLabel = [String: [VisibleDeclaration]]()
		for dependency in instantiable.dependencies where dependency.source == .forwarded {
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
		// An absent declaration follows every declaration of its label, so no receive that reads one reads it instead.
		for absentDeclaration in absentDeclarations {
			childDeclarationsByLabel[absentDeclaration.property.label, default: []].append(absentDeclaration)
		}
		for (label, declarations) in scopeDeclarationsByLabel where unfulfilledReceives.labels.contains(label) {
			for declaration in declarations {
				childReceivableProperties.insert(declaration.property)
				if let instanceProperty = declaration.instanceProperty {
					childReceivableProperties.insert(instanceProperty)
				}
			}
		}
		let loopMembersByChildIndex = loopMembersPassedByReceivedFunctions(of: orderedChildren)

		for child in orderedChildren {
			if case let .alias(property, fulfillingProperty, _, onlyIfAvailable, _) = child.generator.scopeData {
				// The alias is bound in this scope's code, where its fulfilling property is read. An alias that keeps its
				// fulfilling property's label is not in scope where that property is read.
				var fulfillingDeclarationsByLabel = childDeclarationsByLabel
				if fulfillingProperty.label == property.label {
					fulfillingDeclarationsByLabel[property.label] = declarationsByLabel[property.label]
				}
				_ = recordSupply(
					of: fulfillingProperty,
					label: property.label,
					isRequired: !onlyIfAvailable,
					isReportedUnfulfilled: instantiable.dependencies.contains { unfulfilledReceives.contains($0) && $0.property == property },
					among: fulfillingDeclarationsByLabel,
					isPassedNil: Self.aliasIsBoundToNil(onlyIfAvailable: onlyIfAvailable, fulfillingProperty: fulfillingProperty, unavailableProperties: child.unavailableProperties),
				)
			} else if case let .property(childInstantiable, _, _, _, isPropertyCycle, _) = child.generator.scopeData {
				if isPropertyCycle {
					// A scope that closes a cycle constructs nothing: it calls the builder function of the declaration it repeats.
					findings.recordCalls(by: child, of: child.generator.closedOnDeclaration.flatMap { enclosingCycleFunctions[$0] }, among: childDeclarationsByLabel, loopMembers: loopMembersByChildIndex[child.index, default: []])
				} else {
					// This scope calls the child's builder function, which, when a lazy cycle closes on it and it takes
					// parameters, it passes them as each cycle-closing scope does. The function's body reads its parameters,
					// which hide every declaration of their labels where it is called, as generation's do.
					// The function is told apart by the walk's visit of the child, never by its generator, which several places of
					// the tree can share (see `ConstructionMemo`): each place's calls are of a function of its own.
					let function = findings.nextVisitNumber
					findings.recordCalls(by: child, of: function, among: childDeclarationsByLabel, loopMembers: loopMembersByChildIndex[child.index, default: []])
					await findings.append(contentsOf: child.generator.receivedValueSupplies(
						of: childInstantiable,
						unavailableProperties: child.unavailableProperties,
						propertiesGeneratedLater: child.generator.bodyPropertiesGeneratedLater(child.propertiesGeneratedLater),
						declarationsByLabel: child.generator.bodyDeclarations(function: function, enclosing: childDeclarationsByLabel),
						receivableProperties: childReceivableProperties,
						unfulfilledReceives: unfulfilledReceives,
						enclosingCycleFunctions: child.generator.bodyEnclosingCycleFunctions(function: function, enclosing: enclosingCycleFunctions),
						visitNumber: function,
					))
				}
			}
		}
		return findings
	}

	/// What a receive is handed in one place, as `receivedValueSupplies` records it.
	private enum SupplyOutcome {
		/// A declaration's value, an absent one's included.
		case handedValue
		/// `nil`, which generation passes it.
		case passedNil
		/// Nothing: `generate` reports that nothing provides it.
		case unfulfilled
	}

	/// A value a mock tree holds for a parameter that the tier of a public mock it calls omits, which the call passes
	/// `nil` for although the receivers inside the public mock's tree, built inline, would be handed the value.
	struct PublicMockTierOmission: Sendable {
		/// The leaf that calls the public mock.
		let publicMockCall: PublicMockCall
		/// The parameter the tier omits.
		let parameter: StoredPublicMockPlan.Parameter
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
		await publicMockTierOmissions(of: .type(instantiable), propertiesGeneratedLater: [], declarationsByLabel: [:], enclosingCycleFunctions: [:], visitNumber: 0, fillReferenceLocation: nil).judged()
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
		enclosingCycleFunctions: [BuiltDeclaration: Int],
		visitNumber: Int,
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

		var findings = OmissionFindings<PublicMockTierOmission>(nextVisitNumber: visitNumber + 1)
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
				// that function's body's `propertiesGeneratedLater`, as `mockLoweringFillCode(propertiesGeneratedLater:fillPlaceBindings:)` generates
				// them. A call a fill makes is led to by the dependency that leads to the call the fill is passed to.
				let callReferenceLocation = fillReferenceLocation ?? .some(declarationLocationByProperty[childProperty].flatMap(\.self) ?? scopeDeclarationLocation)
				let fillsPropertiesGeneratedLater = child.generator.bodyPropertiesGeneratedLater(child.propertiesGeneratedLater)
				for fill in child.generator.orderedChildrenComputedAfresh(propertiesGeneratedLater: fillsPropertiesGeneratedLater) where fill.generator.fillHole != nil {
					let fillVisitNumber = findings.nextVisitNumber
					await findings.append(contentsOf: fill.generator.publicMockTierOmissions(
						of: .fill(calledType: publicMockCall.type),
						propertiesGeneratedLater: fill.propertiesGeneratedLater,
						declarationsByLabel: childDeclarationsByLabel,
						enclosingCycleFunctions: enclosingCycleFunctions,
						visitNumber: fillVisitNumber,
						fillReferenceLocation: callReferenceLocation,
					))
				}
			} else {
				// This scope calls the child's builder function, which, when a lazy cycle closes on it and it takes parameters,
				// it passes them as each cycle-closing scope does. The function's body reads its parameters, which hide every
				// declaration of their labels where it is called, as generation's do.
				// The function is told apart by the walk's visit of the child, never by its generator, which several places of the
				// tree can share (see `ConstructionMemo`): each place's calls are of a function of its own.
				let function = findings.nextVisitNumber
				findings.recordCalls(by: child, of: function, among: childDeclarationsByLabel)
				await findings.append(contentsOf: child.generator.publicMockTierOmissions(
					of: .type(childInstantiable),
					propertiesGeneratedLater: child.generator.bodyPropertiesGeneratedLater(child.propertiesGeneratedLater),
					declarationsByLabel: child.generator.bodyDeclarations(function: function, enclosing: childDeclarationsByLabel),
					enclosingCycleFunctions: child.generator.bodyEnclosingCycleFunctions(function: function, enclosing: enclosingCycleFunctions),
					visitNumber: function,
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
		forEachGeneratorOfTree { generator in
			if case let .property(instantiable, _, _, _, _, _) = generator.scopeData {
				concreteTypes.insert(instantiable.concreteInstantiable)
			}
		}
		return concreteTypes
	}

	/// The types the tree rooted at this scope builds that its declarations do not name: through a `fulfilledByType:`
	/// string or a `fulfillingAdditionalTypes:` entry, or as what a mock promotes for such a property, and, in a mock, by
	/// calling a hand-written mock another module merges in. The code generated for the tree names each, while no
	/// declaration of the property does, so no file SafeDI read need import its module. A root's file takes its imports
	/// from its world's declarations instead (`TypeFactsImports`), a mock root's beside what lies outside them
	/// (`fulfillersOfMockOutsideTree(mockDefaults:)`), and the tests compare those with this walk of its tree.
	/// - Parameter buildingMock: Whether the tree is a mock's, which builds a type with its hand-written mock.
	func fulfillersOfTree(buildingMock: Bool) async -> Set<FulfillerImports.Fulfiller> {
		var fulfillers = Set<FulfillerImports.Fulfiller>()
		forEachGeneratorOfTree { generator in
			if case let .property(instantiable, property, _, _, _, _) = generator.scopeData {
				let propertyType = property.typeDescription.asInstantiatedType
				fulfillers.formUnion(FulfillerImports.Fulfiller.fulfillers(
					building: instantiable,
					forPropertyOfType: propertyType,
					callingHandWrittenMock: buildingMock && instantiable.mockReturnTypeIsCompatible(withPropertyType: propertyType),
				))
			}
		}
		return fulfillers
	}

	/// Hands `visit` each generator of the tree rooted at this scope, this one first, once each, however many places of
	/// the tree hold it: places share a generator (`ConstructionMemo`), whose subtree is the same at each of them, so a
	/// walk that entered it again at every place visited a tree of layered screens once per path to each screen. The set
	/// of generators visited is the one kind a walk may keep (`generator-design.md`, "Share work by construction"): it
	/// holds an identifier per generator of the tree and dies with the walk. It keys a generator by identity, never by
	/// the type it builds, so one type built for two properties, or two ways, is visited as each.
	private func forEachGeneratorOfTree(_ visit: (ScopeGenerator) -> Void) {
		var visitedGenerators = Set<ObjectIdentifier>()
		// A stack of its own, since a tree can be as deep as the module has types.
		var generatorsToVisit = [self]
		var visitCount = 0
		while let generator = generatorsToVisit.popLast() {
			guard visitedGenerators.insert(ObjectIdentifier(generator)).inserted else { continue }
			visitCount += 1
			visit(generator)
			generatorsToVisit.append(contentsOf: generator.propertiesToGenerate)
		}
		GenerationWork.record(visitCount, by: .collectingTypesOfATree)
	}

	/// The types a mock rooted at this scope names that its world's declarations do not: those a flat parameter of
	/// `mock()` defaults to, which no scope of the tree builds, and the type it extends, which a mock listed in
	/// `additionalMocksToGenerate` extends from another module. Those its tree builds are its world's
	/// (`TypeFactsImports(root:buildingMock:)`).
	/// - Parameter mockDefaults: The hand-written mock a flat parameter of each type defaults to.
	func fulfillersOfMockOutsideTree(mockDefaults: [TypeDescription: FlatParameterMockDefault]) -> Set<FulfillerImports.Fulfiller> {
		var fulfillers = Set<FulfillerImports.Fulfiller>()
		guard case let .root(instantiable, _) = scopeData else { return fulfillers }
		if let fulfiller = FulfillerImports.Fulfiller(instantiable: instantiable) {
			fulfillers.insert(fulfiller)
		}
		// The parameters are worked out again here only for a default that can need an import, which few mocks have.
		let mockDefaults = mockDefaults.filter { !$0.value.fulfillers.isEmpty }
		guard !mockDefaults.isEmpty else { return fulfillers }
		let parameters = mockRootParameters(instantiable: instantiable, mockDefaults: mockDefaults)
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
		var cycleFunction: Int?
		/// Whether the declaration is a field of the struct a public mock hands a fill of its place, which the fill binds:
		/// `declaringType`'s mock hands it the value, which its tree built or its own `mock()` was handed.
		var isHandedToFill = false
		/// Whether the declaration is absent: it stands, in a walk of the value each receive is handed, for the declaration
		/// that will provide a receive of `declaringType` nothing provides yet (see `receivedValueSupplies`).
		var isAbsent = false

		/// Whether a receive of `unwrappedProperty`, or of its optional form, resolves to this declaration.
		func provides(_ unwrappedProperty: Property) -> Bool {
			property.asUnwrappedProperty == unwrappedProperty || instanceProperty?.asUnwrappedProperty == unwrappedProperty
		}

		/// Whether this declaration makes exactly `property` receivable, as validation judges a required receive of it.
		func declares(_ property: Property) -> Bool {
			self.property == property || instanceProperty == property
		}
	}

	/// What a walk finds of the values a tree passes the calls it makes of seams' tiers (`seamTierOmissions`) or of other
	/// modules' public mocks (`publicMockTierOmissions`), or of the value each receive is handed (`receivedValueSupplies`).
	/// A builder function a lazy cycle closes on reads its parameters
	/// (see `CycleParameter`), which the scope that declares it passes as each scope that closes the cycle on it does, so
	/// a call in its body that omits one is judged at the calls of the function, by the declarations they pass, never by
	/// the declarations above the function, as `nonSendableWrapperCaptures` judges a capture of one.
	private struct OmissionFindings<Omission: Sendable>: Sendable {
		/// A call, in the body of a builder function a lazy cycle closes on, that omits a value of one of the function's
		/// parameters: an omission at each declaration a call of the function passes that provides `unwrappedProperty`.
		struct ParameterRead: Sendable {
			let function: Int
			let label: String
			/// The property the call's leaf receives, unwrapped.
			let unwrappedProperty: Property
			/// The omission, given the declaration that provides the value.
			let omission: @Sendable (VisibleDeclaration) -> Omission
		}

		/// A call of a builder function a lazy cycle closes on that passes its parameter of `label` a value: the
		/// declarations of the label where the call is made.
		struct Call: Sendable {
			let function: Int
			let label: String
			let declarations: [VisibleDeclaration]
		}

		/// The number the walk gives the next scope it visits, which tells apart the builder functions the walk enters.
		private(set) var nextVisitNumber: Int
		private(set) var omissions = [Omission]()
		private(set) var parameterReads = [ParameterRead]()
		private(set) var calls = [Call]()

		/// The findings of a visit, whose first visit beneath it is numbered `nextVisitNumber`.
		init(nextVisitNumber: Int) {
			self.nextVisitNumber = nextVisitNumber
		}

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
		mutating func recordCalls(by child: OrderedChild, of function: Int?, among declarationsByLabel: [String: [VisibleDeclaration]]) {
			guard let function else { return }
			for parameter in child.generator.cycleParameters where !child.unavailableProperties.contains(parameter.property) {
				calls.append(Call(function: function, label: parameter.property.label, declarations: declarationsByLabel[parameter.property.label, default: []]))
			}
		}

		/// Adds the findings of a visit this visit made, which numbered the visits beneath it from this visit's
		/// `nextVisitNumber`.
		mutating func append(contentsOf findings: Self) {
			nextVisitNumber = findings.nextVisitNumber
			omissions.append(contentsOf: findings.omissions)
			parameterReads.append(contentsOf: findings.parameterReads)
			calls.append(contentsOf: findings.calls)
		}

		/// The omissions, with each parameter read judged at every call of its function: an omission at each declaration a
		/// call passes that provides what the read receives, or, where a call passes a parameter of an enclosing function,
		/// at the calls of that function in turn.
		func judged() -> [Omission] {
			guard !parameterReads.isEmpty else { return omissions }
			var callsByFunction = [Int: [Call]]()
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

	/// What `receivedValueSupplies` finds: `OmissionFindings` for the value each receive is handed, which also records
	/// what a call that passes a parameter `nil` finds, and the loop members a `__safeDI_<label>_received` function passes.
	/// A type of its own rather than more of `OmissionFindings`: Apple Swift 6.4.2 (Xcode 27.2) crashed with "Found
	/// ownership error" in CopyPropagation compiling `seamTierOmissions` in a release build once `OmissionFindings`
	/// carried an optional of its generic `Omission` and these members, so the tier walks keep the collector they
	/// compiled with before.
	private struct ReceivedValueSupplyFindings: Sendable {
		typealias Omission = ReceivedValueSupply

		/// A call, in the body of a builder function a lazy cycle closes on, that omits a value of one of the function's
		/// parameters: an omission at each declaration a call of the function passes that provides `unwrappedProperty`.
		struct ParameterRead: Sendable {
			let function: Int
			let label: String
			/// The property the call's leaf receives, unwrapped.
			let unwrappedProperty: Property
			/// The omission, given the declaration that provides the value.
			let omission: @Sendable (VisibleDeclaration) -> Omission
			/// What a call that passes the parameter `nil`, or a value of no form the read reads, finds: nothing for an
			/// omission, which needs a value to omit.
			let passedNothing: Omission?
		}

		/// A call of a builder function a lazy cycle closes on that passes its parameter of `label` the declarations of
		/// the label where the call is made, or none where it passes `nil`.
		struct Call: Sendable {
			let function: Int
			let label: String
			let declarations: [VisibleDeclaration]
			/// Whether the call passes `nil` whatever `declarations` provide: generation finds the parameter unavailable
			/// where it is called.
			let passesNil: Bool
		}

		/// The number the walk gives the next scope it visits, which tells apart the builder functions the walk enters.
		private(set) var nextVisitNumber: Int
		private(set) var omissions = [Omission]()
		private(set) var parameterReads = [ParameterRead]()
		private(set) var calls = [Call]()
		/// The concrete type of each scope the walk constructs, in the order it meets them.
		private(set) var constructedTypes: [TypeDescription]
		/// Whether the walk judged every receive it met. It judges none of a tree in which a receive nothing provides, or
		/// the absent declaration beneath one, meets a parameter of a builder function a lazy cycle closes on: the receive
		/// or a receive beneath it reads the parameter, or a call of the function is made beneath it.
		private(set) var isJudged = true

		/// The findings of a visit of a scope that constructs `constructedType`, whose first visit beneath it is numbered
		/// `nextVisitNumber`.
		init(nextVisitNumber: Int, constructedType: TypeDescription) {
			self.nextVisitNumber = nextVisitNumber
			constructedTypes = [constructedType]
		}

		/// Records the omission of a value of `unwrappedProperty` that `provider`, the declaration the omitting call's leaf
		/// would read, provides.
		/// - Parameter passedNothing: What a call of the function `provider` is a parameter of finds where it passes the
		///   parameter `nil`, or `nil` to find nothing there.
		mutating func append(
			reading unwrappedProperty: Property,
			from provider: VisibleDeclaration,
			passedNothing: Omission? = nil,
			omission: @escaping @Sendable (VisibleDeclaration) -> Omission,
		) {
			if let function = provider.cycleFunction {
				parameterReads.append(ParameterRead(function: function, label: provider.property.label, unwrappedProperty: unwrappedProperty, omission: omission, passedNothing: passedNothing))
			} else {
				omissions.append(omission(provider))
			}
		}

		/// Records a finding no declaration provides.
		mutating func append(_ omission: Omission) {
			omissions.append(omission)
		}

		/// Records that the walk met a receive it does not judge.
		mutating func leaveUnjudged() {
			isJudged = false
		}

		/// Records the call `child` makes of `function`, which it declares or closes a cycle on, with the declarations of
		/// each parameter's label among `declarationsByLabel`, where the call is made, and none for those it passes `nil`.
		/// `function` is `nil` for a function that takes no parameters.
		/// - Parameter loopMembers: The members of the loop of builders `child` is a member of, where the scope hands its
		///   wrappers a `__safeDI_<label>_received` function: that function passes a parameter that one of them provides the
		///   member's wrapper made again, whatever `child`'s `unavailableProperties` say (see `ReceivedBuilderLoops`).
		mutating func recordCalls(by child: OrderedChild, of function: Int?, among declarationsByLabel: [String: [VisibleDeclaration]], loopMembers: Set<Property> = []) {
			guard let function else { return }
			for parameter in child.generator.cycleParameters {
				let unwrappedProperty = parameter.property.asUnwrappedProperty
				let isPassedLoopMember = loopMembers.contains(unwrappedProperty) || loopMembers.contains(unwrappedProperty.asOptionalProperty)
				let declarations = declarationsByLabel[parameter.property.label, default: []]
				// A call made beneath a receive nothing provides would pass what its absent declaration stands for, which
				// no call generation makes knows of.
				isJudged = isJudged && !declarations.contains(where: \.isAbsent)
				calls.append(Call(
					function: function,
					label: parameter.property.label,
					declarations: declarations,
					passesNil: !isPassedLoopMember && child.unavailableProperties.contains(parameter.property),
				))
			}
		}

		/// Adds the findings of a visit this visit made, which numbered the visits beneath it from this visit's
		/// `nextVisitNumber`.
		mutating func append(contentsOf findings: Self) {
			nextVisitNumber = findings.nextVisitNumber
			omissions.append(contentsOf: findings.omissions)
			parameterReads.append(contentsOf: findings.parameterReads)
			calls.append(contentsOf: findings.calls)
			constructedTypes.append(contentsOf: findings.constructedTypes)
			isJudged = isJudged && findings.isJudged
		}

		/// The omissions, with each parameter read judged at every call of its function: an omission at each declaration a
		/// call passes that provides what the read receives, or, where a call passes a parameter of an enclosing function,
		/// at the calls of that function in turn.
		func judged() -> [Omission] {
			guard !parameterReads.isEmpty else { return omissions }
			var callsByFunction = [Int: [Call]]()
			for call in calls {
				callsByFunction[call.function, default: []].append(call)
			}
			var omissions = omissions
			for read in parameterReads {
				var judgedFunctions: Set = [read.function]
				var functionsToJudge = [read.function]
				while let function = functionsToJudge.popLast() {
					for call in callsByFunction[function, default: []] where call.label == read.label {
						let provider = call.declarations.first(where: { $0.provides(read.unwrappedProperty) })
						guard !call.passesNil, let provider else {
							// A call passes `nil` where no declaration provides the value, or where one does that is not built yet.
							if let passedNothing = read.passedNothing {
								omissions.append(provider == nil ? passedNothing : passedNothing.passingNil(because: .providerNotYetBuilt))
							}
							continue
						}
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
		// Outside every `@Sendable` function, a tree that makes none captures nothing.
		guard !enclosingSendableBuilders.isEmpty || treeHoldsSendableFunction else { return [] }
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

		// The places each fill stands for, gathered once for the call: a scan of them for each fill compared every place
		// with every fill.
		let placesStoodForByStandInKey = Dictionary(grouping: GenerationWork.taking(fillsStoodFor, by: .findingFillThatStandsForPlace), by: \.standInKey)
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
				// A place this fill stands for (`FillStoodFor`) hands its fill fields equal to this one's that other types can
				// declare, and each capture names the declaration it reads, so the fill's tree is walked once more for each
				// such place, with the place's own hole, as `DependencyTreeGenerator.validateFills` judges it.
				for placeStoodFor in GenerationWork.taking(child.generator.fillKey.flatMap { placesStoodForByStandInKey[$0] } ?? [], by: .findingFillThatStandsForPlace) {
					await captures.append(contentsOf: fillCaptures(
						of: placeStoodFor.hole,
						fill: child.generator,
						propertiesGeneratedLater: child.propertiesGeneratedLater,
						isSendable: buildsInSendableFunction(ofFill: child.generator),
						declarationsByLabel: childDeclarationsByLabel,
						enclosingSendableBuilders: enclosingSendableBuilders,
						chain: chain,
					))
				}
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

	enum ScopeData {
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
		/// How the seam's tree hands each inner seam's enum up from a call whose case is in an enum nested by type. Only
		/// the generation of the seam's own tree reads them, so no signature holds them and no module info file stores
		/// them: a root read from a file, and a root a seam is called through before its signature is computed, have none.
		let callRoutes: [SeamSignature.CallRoute]
		/// The member call each step of the route to each of the seam's own sites makes, in the route's order
		/// (`SeamSignature.Hole.RouteStep.Member`). As `callRoutes`, only the generation of the seam's own tree reads them, so
		/// no signature holds them and no module info file stores them.
		let routeMembersBySite: [SeamSignature.Hole.Site: [SeamSignature.Hole.RouteStep.Member?]]
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
		/// Contrast with a scope's `isPropertyCycle`, which is a
		/// per-root syntactic flag and differs between roots for the same
		/// underlying cycle.
		let cycleEdges: Set<CycleEdge>
		/// For each concrete type with a hand-written mock, the mock's default-valued parameters. A type's
		/// `SafeDIMockConfiguration` takes its defaults from them (`generateConfigurationStruct`), and a property
		/// built with `init` beneath a pruned edge passes the struct's default for each of them
		/// (`MockLowering.argumentsSurfacedWithoutOverride(of:usesMockInitializer:handWrittenDefaults:)`).
		let handWrittenMockDefaultParameters: [TypeDescription: [DefaultParameter]]
		/// The concrete types whose `SafeDIMockConfiguration` is `@Sendable`-typed, from
		/// `TypeFactsSendableConfigurations` across every root. Such a struct stores each labeled
		/// default-valued parameter as a `@Sendable` closure, which the mock body calls where it builds the type,
		/// so the body must know which structs do (`resolveBuilderArguments`).
		let sendableConfigurationTypeNames: Set<String>
		/// What the module's public mocks share, when the module generates one (`generateMock: .public`).
		let publicMockContext: PublicMockContext?
		/// The public mocks other modules generate, by type, whose declarations decide which places of one the mock builds
		/// inline are holes of its module (`ScopeGenerator.holeBuildersByInlinePlace(in:buildersByFamily:foreignPublicMocks:)`).
		let foreignPublicMocks: [TypeDescription: SeamResolution.ForeignPublicMock]
	}

	let scopeData: ScopeData

	/// The fields only a seam's tree, a fill, or a call of another module's public mock sets: every other scope, nearly
	/// all of a tree, holds them at their defaults. A tree has a generator per path, so they are kept behind one
	/// reference (`seamAndFillFieldsStorage`), `nil` where every field is at its default, rather than inline in every
	/// generator; each is read through the accessor of its name.
	struct SeamAndFillFields: Sendable {
		var publicMockCall: PublicMockCall?
		var mockBuilders: DependencyTreeGenerator.ShapedBuilders?
		/// `nil` outside a fill, whose generator reads an empty one.
		var fillCallerReads: FillCallerReads?
		var publicMockLevelFunctions: PublicMockLevelFunctions?
		var fillKey: String?
		var fillFields: [SeamSignature.Hole.Field] = []
		var fillCaseHoles: [SeamSignature.Hole] = []
		var holeCallArguments: [HoleCallArgument] = []
		var builderCallArguments: [BuilderCallArgument] = []
		var fillDispatchers: [FillDispatcher] = []
		var passedUpHoles: [SeamSignature.Hole] = []
		var referencedFillNamesByKey: [String: String] = [:]
		var publicMockLevelReentries: [String: PublicMockLevelFunctions.Reentry] = [:]
		var fillStructBoundLabels: Set<String> = []
		var fillDeferredLabelsHiddenByReenteringCalls: [String: Set<String>] = [:]
		var fillDeferredLabelsReadInsideSendableFunction: [String: Set<String>] = [:]
		var fillSendableWrapperReads: [String: [String: Property]] = [:]
		var fillLabelsReadOnlyAsPlaceField: [String: Set<String>] = [:]
		var fillLabelsHandedAsMemo: Set<String> = []
		var fillPlainMemoRoutesOfSendableWrapperReads: [String: [FillDispatcher.PlainMemoRoute]] = [:]
		var fillMemoOriginsByLabel: [String: [SeamSignature.Hole.Field.SeamParameterOrigin]] = [:]
		var fillKeysReferencedFromSendableFunction: Set<String> = []
		var sendableFillKeys: Set<String> = []
		var inlinableFillKeys: Set<String> = []
		var namedFillKeys: Set<String> = []
		var valuesBindings: [SeamHoles.ValuesBinding] = []
		var memberCallsInsideFunction: [SeamHoles.ValuesBinding] = []
		var innerScopesCalledWithForwardedValue: [String] = []
		var namesBoundBySeam: Set<String> = []
		var boxedLoops: [Int: String] = [:]
		var loopLevelsTypesInTree: [String: String] = [:]
		var builtInlineSeamComment: String?
		var isUnavailableDependency = false
		var publicMockOverrideBuilders: [String: PublicMockOverrideBuilder]?
		var fillFieldSelection: FillFieldSelection?
		var siteCarrierUse: SeamCarrierValues.Use?
		var siteRouteMembers: [SeamSignature.Hole.RouteStep.Member?] = []
		var fillCarrierUse: SeamCarrierValues.Use?
		var fillsStoodFor: [FillStoodFor] = []
		var buildsFillOfEveryPlace = false

		/// Whether any field differs from its default.
		var holdsAnything: Bool {
			publicMockCall != nil
				|| !fillsStoodFor.isEmpty
				|| buildsFillOfEveryPlace
				|| mockBuilders != nil
				|| fillCallerReads != nil
				|| publicMockLevelFunctions != nil
				|| fillKey != nil
				|| !fillFields.isEmpty
				|| !fillCaseHoles.isEmpty
				|| !holeCallArguments.isEmpty
				|| !builderCallArguments.isEmpty
				|| !fillDispatchers.isEmpty
				|| !passedUpHoles.isEmpty
				|| !referencedFillNamesByKey.isEmpty
				|| !publicMockLevelReentries.isEmpty
				|| !fillStructBoundLabels.isEmpty
				|| !fillDeferredLabelsHiddenByReenteringCalls.isEmpty
				|| !fillDeferredLabelsReadInsideSendableFunction.isEmpty
				|| !fillSendableWrapperReads.isEmpty
				|| !fillLabelsReadOnlyAsPlaceField.isEmpty
				|| !fillLabelsHandedAsMemo.isEmpty
				|| !fillPlainMemoRoutesOfSendableWrapperReads.isEmpty
				|| !fillMemoOriginsByLabel.isEmpty
				|| !fillKeysReferencedFromSendableFunction.isEmpty
				|| !sendableFillKeys.isEmpty
				|| !inlinableFillKeys.isEmpty
				|| !namedFillKeys.isEmpty
				|| !valuesBindings.isEmpty
				|| !memberCallsInsideFunction.isEmpty
				|| !innerScopesCalledWithForwardedValue.isEmpty
				|| !namesBoundBySeam.isEmpty
				|| !boxedLoops.isEmpty
				|| !loopLevelsTypesInTree.isEmpty
				|| builtInlineSeamComment != nil
				|| isUnavailableDependency
				|| publicMockOverrideBuilders != nil
				|| fillFieldSelection != nil
				|| siteCarrierUse != nil
				|| !siteRouteMembers.isEmpty
				|| fillCarrierUse != nil
		}
	}

	/// `SeamAndFillFields` behind a reference.
	final class SeamAndFillFieldsStorage: Sendable {
		init(_ fields: SeamAndFillFields) {
			self.fields = fields
		}

		let fields: SeamAndFillFields

		/// `fields` behind a reference, or `nil` where they hold nothing.
		static func storing(_ fields: SeamAndFillFields) -> SeamAndFillFieldsStorage? {
			fields.holdsAnything ? SeamAndFillFieldsStorage(fields) : nil
		}
	}

	/// See `SeamAndFillFields`.
	nonisolated private let seamAndFillFieldsStorage: SeamAndFillFieldsStorage?
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
	/// The labels of those of `cycleParameters` this scope passes `nil`, before any sibling's ordering is known.
	nonisolated var labelsOfCycleParametersPassedNil: Set<String> {
		Set(cycleParameters.lazy.filter { self.cycleParameterUnavailableProperties.contains($0.property) }.map(\.property.label))
	}

	/// The received properties in scope only as the instance of a `LazilyInstantiated` property where this scope passes
	/// `cycleParameters`: for a scope that declares the function, those its parameters do not hide; for any other scope,
	/// `lazilyInstantiatedInstanceProperties`.
	private let callSiteLazilyInstantiatedInstanceProperties: Set<Property>
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
	nonisolated var boxedLoops: [Int: String] {
		seamAndFillFieldsStorage?.fields.boxedLoops ?? [:]
	}

	/// The declaration of each class of `boxedLoops` in this tree, by its name, which the seam whose tree it is declares
	/// beside its initializers.
	nonisolated var loopLevelsTypesInTree: [String: String] {
		seamAndFillFieldsStorage?.fields.loopLevelsTypesInTree ?? [:]
	}

	/// For a call of another module's public mock, what each level function a call inside one of its fills re-enters takes of
	/// the caller's scope, by its dispatcher's key, where it takes anything (`PublicMockLevelFunctions.levelReentries(amongKeys:)`),
	/// which the next pass of `Scope.createScopeGenerator` hands those calls. Empty for nearly every scope.
	nonisolated var publicMockLevelReentries: [String: PublicMockLevelFunctions.Reentry] {
		seamAndFillFieldsStorage?.fields.publicMockLevelReentries ?? [:]
	}

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
	/// Whether this scope closes a lazy cycle, or a scope of its generated subtree does. Only such a scope can find other
	/// cycle parameters, or receive other properties, in a pass after the first (see `CycleParameterPlan`).
	nonisolated let holdsCycleClosingScope: Bool
	/// What `CycleParameterPlan` reads to search this scope's cycle parameters again, kept only where
	/// `holdsCycleClosingScope`, which few scopes are; `nil` everywhere else.
	nonisolated let cycleParameterSearchInputs: CycleParameterSearchInputs?
	/// The names a parameter of the construction of a type in this subtree declares `@escaping`, each a function type
	/// (`TypeDescription.nameDeclaredEscaping`). A parameter of a function generated code declares with such a type is
	/// spelled `@escaping`, or it could not be passed to that construction. Every receiver of a property of such a type
	/// stores it, so it declares its parameter `@escaping`, which puts the name here wherever the property is passed. A
	/// scope that calls another module's public mock, or a seam, has no scopes for what is beneath it, so the call carries
	/// the names (`PublicMockCall.typesDeclaredEscaping`, `SeamCall.typesDeclaredEscaping`).
	let typesDeclaredEscaping: Set<TypeDescription>
	/// Received properties that are optional and not created by a parent.
	let unavailableOptionalProperties: Set<Property>
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
	nonisolated var propertiesToGenerate: [ScopeGenerator] {
		propertiesToGenerateSlot.value
	}

	/// `propertiesToGenerate`, held in a slot that releases them one level at a time: a tree of generators can be as
	/// deep as the module has types.
	private let propertiesToGenerateSlot: DeferredReleaseSlot<[ScopeGenerator]>
	/// Properties that this scope declares as a `let` constant, and those its type instantiates that a mock is
	/// passed instead (see `Scope.propertiesToDeclare`).
	let propertiesToDeclare: Set<Property>
	/// The `@Instantiated` dependencies of this scope's type that a mock is passed because no scope builds them (see
	/// `Scope.instantiatedDependenciesNotGenerated`), which the scopes this scope builds read as they would read the
	/// property this scope generated.
	private let instantiatedDependenciesNotGenerated: [Dependency]
	/// For a scope that calls a seam, the builders the call passes, in builder-label order; empty otherwise.
	nonisolated private var holeCallArguments: [HoleCallArgument] {
		seamAndFillFieldsStorage?.fields.holeCallArguments ?? []
	}

	/// What this scope's seam call passes each builder, in the order the seam takes them.
	nonisolated private var builderCallArguments: [BuilderCallArgument] {
		seamAndFillFieldsStorage?.fields.builderCallArguments ?? []
	}

	/// The dispatchers this scope's seam call declares.
	nonisolated private var fillDispatchers: [FillDispatcher] {
		seamAndFillFieldsStorage?.fields.fillDispatchers ?? []
	}

	/// For a scope that calls another module's public mock and fills a builder, the level functions its call declares for
	/// the builders it fills (`PublicMockLevelFunctions`); `nil` for every other scope.
	nonisolated private var publicMockLevelFunctions: PublicMockLevelFunctions? {
		seamAndFillFieldsStorage?.fields.publicMockLevelFunctions
	}

	/// For a scope that calls a seam, the holes of that seam whose builders the call passes up from the builders of
	/// the seam whose tree makes the call, in builder-label order: the caller's declarations hold no type that fulfills
	/// them. Empty otherwise.
	nonisolated var passedUpHoles: [SeamSignature.Hole] {
		seamAndFillFieldsStorage?.fields.passedUpHoles ?? []
	}

	/// Whether a scope in this generator's subtree passes up a builder (see `passedUpHoles`).
	let passesUpBuilder: Bool
	/// Whether this scope, or a scope in its subtree, calls a seam inside a fill of an enclosing call and passes one of that
	/// call's fills or dispatchers by name (`enclosingFillsPassed`): the call re-enters the enclosing call's fill.
	let holdsCallReenteringEnclosingFill: Bool
	/// For a fill, its key (see `fillKey(of:)`); `nil` for every other generator.
	nonisolated var fillKey: String? {
		seamAndFillFieldsStorage?.fields.fillKey
	}

	/// What a fill's tree is generated with of `propertiesGeneratedLater`, the properties the caller builds after the call:
	/// each field the fill binds (`fillStructBoundLabels`) hides the caller's declaration of its label, as the nearest
	/// declaration inline reads, so a receive of it is handed the field, which the route's level binds or, on a route that
	/// binds none, the root dispatcher or level function hands `nil` for a value the caller builds later.
	nonisolated private func fillBodyPropertiesGeneratedLater(_ propertiesGeneratedLater: Set<Property>) -> Set<Property> {
		let boundLabels = fillStructBoundLabels
		guard !boundLabels.isEmpty, !propertiesGeneratedLater.isEmpty else { return propertiesGeneratedLater }
		return propertiesGeneratedLater.filter { !boundLabels.contains($0.label) }
	}

	/// For a fill, the labels of the fields of its hole's struct it binds from the struct: every field but those bound
	/// from a parameter the seam defers, which the fill reads from the caller's scope, as inline, unless a call inside a
	/// fill of the same seam call passes this fill on beneath another declaration of the label
	/// (`fillDeferredLabelsHiddenByReenteringCalls`). Empty for every other generator.
	nonisolated var fillStructBoundLabels: Set<String> {
		seamAndFillFieldsStorage?.fields.fillStructBoundLabels ?? []
	}

	/// For a seam call, by the key of each of its fills, the labels of the hole's fields bound from deferred parameters
	/// that a declaration on the path from a fill of the call to a call inside it that passes the fill on hides: the
	/// fill, one function, would read the outer call's declaration for every call, so it reads the struct's field for
	/// them instead (see `DependencyTreeGenerator.hiddenByReenteringCalls(ofFills:)`). Empty for nearly every scope.
	nonisolated var fillDeferredLabelsHiddenByReenteringCalls: [String: Set<String>] {
		seamAndFillFieldsStorage?.fields.fillDeferredLabelsHiddenByReenteringCalls ?? [:]
	}

	/// For a seam call, by the key of each of its fills, the labels of the hole's fields bound from deferred parameters held
	/// in a `LazilyInstantiated` that the fill binds from its struct and that its tree reads inside a `@Sendable` function,
	/// which cannot capture the memo: the fill binds the struct's by-value member for them instead (see
	/// `Scope.fillUnderConstruction`). Empty for nearly every scope.
	/// A place of a seam call whose fill this call did not build, because the fill of another place of its case, built from
	/// values equal to its own in everything that fill's tree reads, stands for it.
	///
	/// A caller generates one function per case, the first place's, and builds a fill for the other places only to judge
	/// each (`DependencyTreeGenerator.validateFills`). A seam reached along thousands of paths has thousands of places in a
	/// few hundred cases, and every place of a case nearly always hands its fill the same values, so the call builds the
	/// fill of the first of them and judges the others against that fill's tree, each with its own hole.
	struct FillStoodFor: Sendable {
		/// The place, which every judgement of it reads.
		let hole: SeamSignature.Hole
		/// The key of the fill the call did not build (`ScopeGenerator.fillKey(of:)`).
		let key: String
		/// The key of the fill that stands for it, a child of the call's generator.
		let standInKey: String
		/// How many fills the call built before this place, in the order of the call's arguments, which the judgement of a
		/// call's places follows.
		let builtFillCountBefore: Int
	}

	/// The places of this scope's seam call whose fills other places' stand for, in the order of the call's arguments.
	/// Memory: one hole per such place, which the signature the call reads holds already, for as long as the generator.
	nonisolated var fillsStoodFor: [FillStoodFor] {
		seamAndFillFieldsStorage?.fields.fillsStoodFor ?? []
	}

	/// Whether this scope's seam call builds a fill for every place from this pass on, because a pass found something a
	/// place's own fill could be asked that a fill standing for it does not answer (see `init`).
	nonisolated var buildsFillOfEveryPlace: Bool {
		seamAndFillFieldsStorage?.fields.buildsFillOfEveryPlace ?? false
	}

	/// The fill among this scope's children that the judgement of the place `site` reads: the place's own, or the one that
	/// stands for it.
	nonisolated func fill(judgingPlaceAt site: SeamSignature.Hole.Site) -> ScopeGenerator? {
		if let fill = children.first(where: { $0.fillHole?.site == site }) {
			fill
		} else if let standInKey = fillsStoodFor.first(where: { $0.hole.site == site })?.standInKey {
			children.first { $0.fillKey == standInKey }
		} else {
			nil
		}
	}

	nonisolated var fillDeferredLabelsReadInsideSendableFunction: [String: Set<String>] {
		seamAndFillFieldsStorage?.fields.fillDeferredLabelsReadInsideSendableFunction ?? [:]
	}

	/// For a seam call, by the key of each of its fills, the labels some route hands the fill as a memo
	/// (`fillLabelsHandedAsMemo`) that its tree also reads as a `SendableLazilyInstantiated`, each with the instance property
	/// that wrapper holds: the fill takes that wrapper as the memo where every route can hand it
	/// (`FillDispatcher.memosHanded(toFillOf:labels:readingSendableWrapper:among:)`). Empty for nearly every scope.
	nonisolated var fillSendableWrapperReads: [String: [String: Property]] {
		seamAndFillFieldsStorage?.fields.fillSendableWrapperReads ?? [:]
	}

	/// For a seam call, by the key of each of its fills, the labels some route hands the fill as a memo
	/// (`fillLabelsHandedAsMemo`) whose tree reads the label but neither the memo's value nor carries it to a site: it reads
	/// the place's own field, the wrapper a type further out declares, as inline reads that declaration. The fill takes that
	/// field rather than the memo, and the levels hand it on past the deferring seam's
	/// (`FillDispatcher.Case.handsOn(_:)`). A label stays found on every later pass, where no memo is handed to show it.
	/// Empty for nearly every scope.
	nonisolated var fillLabelsReadOnlyAsPlaceField: [String: Set<String>] {
		seamAndFillFieldsStorage?.fields.fillLabelsReadOnlyAsPlaceField ?? [:]
	}

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
	nonisolated var fillLabelsHandedAsMemo: Set<String> {
		seamAndFillFieldsStorage?.fields.fillLabelsHandedAsMemo ?? []
	}

	/// For a fill, by each label it takes a `LazilyInstantiated` memo of while its tree also reads the label as a
	/// `SendableLazilyInstantiated`, the routes that hand it a seam's `LazilyInstantiated`
	/// (`FillDispatcher.memosHanded(toFillOf:labels:readingSendableWrapper:among:)`): no such memo is the wrapper, so
	/// `DependencyTreeGenerator.validateFills(inTreesRootedAt:callerModule:)` reports the read. Empty for every other generator.
	nonisolated var fillPlainMemoRoutesOfSendableWrapperReads: [String: [FillDispatcher.PlainMemoRoute]] {
		seamAndFillFieldsStorage?.fields.fillPlainMemoRoutesOfSendableWrapperReads ?? [:]
	}

	/// For a fill, by each label some route hands it as the memo of a seam's deferred parameter
	/// (`FillDispatcher.memosHanded(toFillOf:labels:readingSendableWrapper:among:)`), each such parameter: the seam's tree, as
	/// the caller fills it, receives the label wherever the fill's tree reads that memo, so
	/// `DependencyTreeGenerator.validateFills(inTreesRootedAt:callerModule:)` judges the fill's reads against the parameter. Empty
	/// for every other generator.
	nonisolated var fillMemoOriginsByLabel: [String: [SeamSignature.Hole.Field.SeamParameterOrigin]] {
		seamAndFillFieldsStorage?.fields.fillMemoOriginsByLabel ?? [:]
	}

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
		guard let fillFieldSelection else { return [] }
		var parameterFields = [SeamSignature.Hole.Field]()
		appendParameterFields(of: fillFieldSelection, to: &parameterFields)
		return parameterFields
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
		guard let fillFieldSelection else { return [] }
		var fields = [SeamSignature.Hole.Field]()
		if takingPayloadFields {
			// Each is the fill's own field of the payload's label, which says how the fill binds it, as its body reads it: a
			// deferred parameter's memo where it `bindsMemo`, which the member hands it in place of the value.
			fields.reserveCapacity(fillFieldSelection.payloadFieldIndices.count + fillFieldSelection.parameterFieldIndices.count)
			for index in fillFieldSelection.payloadFieldIndices {
				fields.append(fillFields[index])
			}
		}
		appendParameterFields(of: fillFieldSelection, to: &fields)
		return fields
	}

	/// Appends `fillParameterFields`: each field `selection` names, in the form the root dispatcher reads its label from the
	/// caller's scope where it does (`fillCallerReads`), then the scopes the fill is handed.
	nonisolated private func appendParameterFields(of selection: FillFieldSelection, to fields: inout [SeamSignature.Hole.Field]) {
		for index in selection.parameterFieldIndices {
			let field = fillFields[index]
			fields.append(fillCallerReads.parameterByLabel[field.property.label] ?? field)
		}
		fields.append(contentsOf: fillCallerReads.innerScopeParameters)
	}

	/// For a fill of a place whose case is nested by type, which of its fields (by index into `fillFields`) it takes
	/// (`fillParameterFields`, `fillMemberParameterFields(takingPayloadFields:)`), decided once, when the fill's generator is
	/// built: whether the generator it builds its type with reads a field, which these decide, never changes, and a level
	/// function's member asks for them once per call it makes. It holds indices, not fields, and no generator, so it keeps
	/// alive nothing the fill's generator does not.
	final class FillFieldSelection: Sendable {
		init?(hole: SeamSignature.Hole, boundLabels: Set<String>, fields: [SeamSignature.Hole.Field], child: ScopeGenerator) {
			guard let enumPlace = hole.enumPlace else { return nil }
			let carried = Set(enumPlace.values.map(\.property.label))
			var firstBoundIndexByLabel = [String: Int]()
			var parameterFieldIndices = [Int]()
			for (index, field) in fields.enumerated() where boundLabels.contains(field.property.label) {
				if firstBoundIndexByLabel[field.property.label] == nil {
					firstBoundIndexByLabel[field.property.label] = index
				}
				if !carried.contains(field.property.label), child.reads(field.property) || child.fieldsCarriedBySites.contains(field.property) {
					parameterFieldIndices.append(index)
				}
			}
			self.parameterFieldIndices = parameterFieldIndices
			// A payload value's field is the first bound field of its label, as a search of the bound fields in order finds it.
			payloadFieldIndices = enumPlace.values.compactMap { value in
				guard let index = firstBoundIndexByLabel[value.property.label],
				      child.reads(value.property) || child.fieldsCarriedBySites.contains(value.property)
				else { return nil }
				return index
			}
		}

		/// The bound fields not carried by the case's payload that the fill's tree reads or a site inside it carries.
		let parameterFieldIndices: [Int]
		/// For each value of the case's payload the fill's tree reads or a site inside it carries, the fill's bound field of
		/// its label.
		let payloadFieldIndices: [Int]
	}

	/// For a fill of a place whose case is nested by type, the fields it takes (`FillFieldSelection`); `nil` for every other
	/// generator.
	nonisolated private var fillFieldSelection: FillFieldSelection? {
		seamAndFillFieldsStorage?.fields.fillFieldSelection
	}

	/// For a fill or a mock root, the labels among `labels` its tree reads inside a `@Sendable` function, or hands to a
	/// nested seam that takes them `@Sendable`, where no declaration inside the tree hides them, as
	/// `DependencyTreeGenerator.receivers(in:of:instantiables:)` finds a seam's tree reading its parameters
	/// (`ParameterReads`): the fill's bound fields, or the mock root's overrides, stand where the seam's parameters do. The
	/// fill's or mock's own function is not one of those functions: what it binds is a local of that function. A scope
	/// that closes a lazy cycle reads no label from
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
	nonisolated var fillCallerReads: FillCallerReads {
		seamAndFillFieldsStorage?.fields.fillCallerReads ?? FillCallerReads()
	}

	/// For a fill, the fields it can bind: its hole's struct's, or, for a place whose case is nested by type, those of every
	/// place of the case, each label once (see `init(fill:…)`). Empty for every other generator.
	nonisolated var fillFields: [SeamSignature.Hole.Field] {
		seamAndFillFieldsStorage?.fields.fillFields ?? []
	}

	/// For a fill, the places it stands for: its hole, or, for a place whose case is nested by type, every place of the case,
	/// in the order the builders reach them. Empty for every other generator.
	nonisolated var fillCaseHoles: [SeamSignature.Hole] {
		seamAndFillFieldsStorage?.fields.fillCaseHoles ?? []
	}

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
	nonisolated var referencedFillNamesByKey: [String: String] {
		seamAndFillFieldsStorage?.fields.referencedFillNamesByKey ?? [:]
	}

	/// The keys of `referencedFillNamesByKey` referred to from inside a `@Sendable` builder function that does not
	/// enclose the fill, or passed to a seam that takes the fill `@Sendable`.
	nonisolated var fillKeysReferencedFromSendableFunction: Set<String> {
		seamAndFillFieldsStorage?.fields.fillKeysReferencedFromSendableFunction ?? []
	}

	/// For a seam call, the keys of its fills whose function is `@Sendable`, which `buildsInSendableFunction(ofFill:)` reads
	/// (see `sendableFills(of:referencedFromSendableFunctions:)`).
	nonisolated private var sendableFillKeys: Set<String> {
		seamAndFillFieldsStorage?.fields.sendableFillKeys ?? []
	}

	/// For a seam call, the keys of its fills generated in the one dispatcher case that calls them, not as functions of
	/// their own: a fill nothing else refers to by name, which is `@Sendable` exactly when its dispatcher is.
	nonisolated private var inlinableFillKeys: Set<String> {
		seamAndFillFieldsStorage?.fields.inlinableFillKeys ?? []
	}

	/// The keys of the fills and dispatchers of enclosing calls that this scope's code, or a scope's beneath it, calls or
	/// passes by name.
	nonisolated var namedFillKeys: Set<String> {
		seamAndFillFieldsStorage?.fields.namedFillKeys ?? []
	}

	/// The payloads of the cases on the routes to the places beneath this scope that the seam's tree binds just before this
	/// scope's builder function (`SeamHoles.valuesBindings(at:)`): empty but where a case nested by type leads through this
	/// scope's property.
	nonisolated private var valuesBindings: [SeamHoles.ValuesBinding] {
		seamAndFillFieldsStorage?.fields.valuesBindings ?? []
	}

	/// For a hole whose case is a carrier's, how its member takes its values (`SeamHoles.carrierSite(at:)`); `nil` elsewhere.
	nonisolated private var siteCarrierUse: SeamCarrierValues.Use? {
		seamAndFillFieldsStorage?.fields.siteCarrierUse
	}

	/// For a hole's site, the member call each step of its route makes (`SeamHoles.routeMembers(at:)`); empty elsewhere.
	nonisolated var siteRouteMembers: [SeamSignature.Hole.RouteStep.Member?] {
		seamAndFillFieldsStorage?.fields.siteRouteMembers ?? []
	}

	/// For a fill of a place whose case is a seam's carrier's, how the fill takes the case's values: the struct of the run
	/// they end, then each value after it (`SeamCarrierValues.Use`); `nil` for every other generator.
	nonisolated private var fillCarrierUse: SeamCarrierValues.Use? {
		seamAndFillFieldsStorage?.fields.fillCarrierUse
	}

	/// The structs the member calls the seam's tree makes at the top of this scope's builder function return, a `@Sendable`
	/// function (`SeamHoles.memberCallsInsideFunction(at:)`): empty but where a builder struct's `@Sendable` member leads
	/// through this scope's property.
	nonisolated private var memberCallsInsideFunction: [SeamHoles.ValuesBinding] {
		seamAndFillFieldsStorage?.fields.memberCallsInsideFunction ?? []
	}

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
	nonisolated private var innerScopesCalledWithForwardedValue: [String] {
		seamAndFillFieldsStorage?.fields.innerScopesCalledWithForwardedValue ?? []
	}

	/// The payloads `valuesBindings` binds before this scope's builder function in a mock's tree: each field read as the
	/// scope's parent reads its label, as production's are.
	nonisolated var valuesBindingsBeforeBuilderFunction: [MockValuesBinding] {
		valuesBindings.map { MockValuesBinding(binding: $0, lazilyInstantiatedInstanceProperties: callSiteLazilyInstantiatedInstanceProperties) }
	}

	/// The member calls `memberCallsInsideFunction` makes at the top of this scope's `@Sendable` builder function in a
	/// mock's tree: each field read as the scope's parent reads its label.
	nonisolated var memberCallsInsideBuilderFunction: [MockValuesBinding] {
		memberCallsInsideFunction.map { MockValuesBinding(binding: $0, lazilyInstantiatedInstanceProperties: callSiteLazilyInstantiatedInstanceProperties) }
	}

	/// Whether this scope, or a scope of its generated subtree, calls another module's seam or public mock or is a fill: only
	/// such a tree has anything `DependencyTreeGenerator.validateFills(inTreesRootedAt:callerModule:compilesGeneratedMocks:)`
	/// judges, so its walk skips every other subtree. Set once, bottom-up, by the initializer that builds a scope's generator
	/// (from `seamCall`, `publicMockCall`, `fill` and the children's flags), and `false` for an alias's or a hole's generator,
	/// which holds neither; `validateFills` is its only reader.
	let treeHoldsCallOrFill: Bool

	/// Whether this scope, or a scope of its generated subtree, is or makes a function that can be `@Sendable`: a builder
	/// function that is, a property of a `Sendable` wrapper (a cycle-closing scope calls its function inside the wrapper's
	/// closure), a fill, or a call of a seam that defers a parameter `@Sendable`. Only such a tree can capture anything
	/// outside every `@Sendable` function, so `nonSendableWrapperCaptures` walks no other subtree there. Set once,
	/// bottom-up, by the initializer that builds a scope's generator, and `false` for an alias's or a hole's generator,
	/// which the walk does not enter; `nonSendableWrapperCaptures` is its only reader.
	let treeHoldsSendableFunction: Bool

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
		Self.startsAsCarrier(child, placeHoldingProperties: placeHoldingProperties)
	}

	/// `startsAsCarrier(_:)` of a scope whose place-holding properties are `placeHoldingProperties`.
	nonisolated private static func startsAsCarrier(_ child: ScopeGenerator, placeHoldingProperties: Set<Property>?) -> Bool {
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
	// D1 lane hook (lane B): the mock lowering reads which by-value receives pass a lazy wrapper's instance.
	/// `lazilyInstantiatedInstanceProperties`, read by the mock lowering.
	nonisolated var mockLoweringLazilyInstantiatedInstanceProperties: Set<Property> {
		lazilyInstantiatedInstanceProperties
	}

	// D1 lane hook (lane D): the mock lowering reads whether an alias reads the instance of a `LazilyInstantiated` its scope
	// holds.
	nonisolated var mockLoweringFulfillingPropertyIsLazilyInstantiatedInstance: Bool {
		fulfillingPropertyIsLazilyInstantiatedInstance
	}

	// D1 lane hook (lane B): the mock lowering reads which cycle arguments pass a lazy wrapper's instance.
	/// `callSiteLazilyInstantiatedInstanceProperties`, read by the mock lowering.
	nonisolated var mockLoweringCallSiteLazilyInstantiatedInstanceProperties: Set<Property> {
		callSiteLazilyInstantiatedInstanceProperties
	}

	/// Whether the property an alias renames is in scope only as the instance of a `LazilyInstantiated` property.
	private let fulfillingPropertyIsLazilyInstantiatedInstance: Bool
	/// The by-value property with which this scope’s siblings and their subtrees receive the instance of the
	/// lazily instantiated property this scope declares. `nil` when it declares none.
	private let declaredLazilyInstantiatedInstanceProperty: Property?
	/// `declaredLazilyInstantiatedInstanceProperty`, read by the mock lowering.
	nonisolated var mockLoweringDeclaredLazilyInstantiatedInstanceProperty: Property? {
		declaredLazilyInstantiatedInstanceProperty
	}

	/// For an `onlyIfAvailable` alias, whether the declared property it is bound from may be `nil`: an optional
	/// property it reads in place of its fulfilling property's non-optional form, a parameter made optional, or a
	/// seam's optional parameter. `false` for every other scope.
	private let fulfillingBindingIsOptional: Bool
	/// For an alias the seam root declares that keeps the label of a deferred parameter it retypes, the call of the
	/// parameter's autoclosure it is bound from (`SeamRoot.autoclosureCallByLabel`); `nil` for every other generator.
	private let fulfillingExpression: String?
	let property: Property?
	/// The comment that ends each line that constructs this scope's type (`Scope.builtInlineSeamComment`).
	nonisolated private var builtInlineSeamComment: String? {
		seamAndFillFieldsStorage?.fields.builtInlineSeamComment
	}

	/// Whether this scope stands for an `@Instantiated(onlyIfAvailable: true)` property no production declaration fulfills,
	/// which it binds to `nil` (`Scope.isUnavailableDependency`).
	nonisolated var isUnavailableDependency: Bool {
		seamAndFillFieldsStorage?.fields.isUnavailableDependency ?? false
	}

	/// Whether this scope, in the tree of a fill a mock declares for another module's public mock, builds its type with
	/// its hand-written mock, as the mock's tree built inline would (`Scope.createScopeGenerator`).
	let constructsWithHandWrittenMock: Bool
	/// How a mock tree calls the public mock another module generated for this scope's type, or `nil` for a scope
	/// that builds its type (see `Scope.publicMockCall`).
	nonisolated var publicMockCall: PublicMockCall? {
		seamAndFillFieldsStorage?.fields.publicMockCall
	}

	/// For a public mock's root, the builders its `mock()` takes; `nil` for every other generator.
	nonisolated var mockBuilders: DependencyTreeGenerator.ShapedBuilders? {
		seamAndFillFieldsStorage?.fields.mockBuilders
	}

	/// In a seam's tree, the names its generated initializer binds for its deferred parameters and its builders, which
	/// code anywhere in the tree may read and no `__safeDI_<label>_received` function may hide (see
	/// `namesReceivedFunctionsAvoid`). Empty outside a seam's tree.
	nonisolated private var namesBoundBySeam: Set<String> {
		seamAndFillFieldsStorage?.fields.namesBoundBySeam ?? []
	}

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
	/// A deliberate gap, commented where the member is typed (`MockLowering.PublicMockCallNode.overrideClosureType`): the closure could be
	/// offered there by unwrapping the called mock's struct in generated code, a later addition that breaks nothing.
	///
	/// Computed once, when the generator is built, from values that never change.
	nonisolated var publicMockOverrideBuilders: [String: PublicMockOverrideBuilder]? {
		seamAndFillFieldsStorage?.fields.publicMockOverrideBuilders
	}

	nonisolated private static func publicMockOverrideBuilders(
		publicMockCall: PublicMockCall?,
		builderCallArguments: [BuilderCallArgument],
		builtInstantiable: Instantiable?,
		publicMockLevelFunctions: PublicMockLevelFunctions?,
		children propertiesToGenerate: [ScopeGenerator],
	) -> [String: PublicMockOverrideBuilder]? {
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

		/// The expression handed, given the expression the call passes the called mock's parameter of each label, and the
		/// builder `mock()` takes for the places of the fill, if any (`FillPlaceBindings.HoleBuilder`), which the closure calls
		/// in place of the fill where it is passed, so that it is never ignored.
		func expression(argumentByLabel: [String: String], holeBuilder: FillPlaceBindings.HoleBuilder?) -> String {
			switch self {
			case let .callersBuilder(value):
				return value
			case let .fill(_, functionName, parameterLabels, returnsWrapperBuilder, forwardsNothing):
				let arguments = parameterLabels.map { "\($0.spelledAsArgumentLabel): \(argumentByLabel[$0] ?? $0)" }.joined(separator: ", ")
				let call = "\(functionName)(\(arguments))"
				if !returnsWrapperBuilder {
					return holeBuilder?.overrideValue(fillsCall: call) ?? "{ \(call) }"
				} else if forwardsNothing {
					return holeBuilder?.overrideValue(fillsCall: "\(call)(())") ?? "{ \(call)(()) }"
				} else {
					return holeBuilder?.wrapperBuilderValue(fillsCall: call) ?? call
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
	/// declares before the call, generated with `propertiesGeneratedLater` and `fillPlaceBindings`, the names the mock root
	/// hands the call: each builds the hole's property as the module that declares the fulfilling type builds it. Stored
	/// nowhere, since mock roots that share the call each hand it their own names (`construction-memo-calls.md`).
	func mockLoweringFillCode(propertiesGeneratedLater: Set<Property>, fillPlaceBindings: FillPlaceBindings) async throws -> [String] {
		try await generateProperties(
			propertiesGeneratedLater: propertiesGeneratedLater,
			enclosingFunctionNames: [:],
			leadingMemberWhitespace: "",
			fillPlaceBindings: fillPlaceBindings,
		).map { $0.spelled() }
	}

	/// Every argument of `generatePropertyCode` but `codeGeneration`, which is `.dependencyTree` wherever the key is made,
	/// is in this key: a construction memo can share one generator between several
	/// places, each emitting it with its own arguments, and the memo oracle compares construction only, so an emission
	/// argument left out of the key would hand one place the code another place's arguments made.
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
	nonisolated private var orderedPropertiesToGenerate: LazyMapSequence<[Int], ScopeGenerator> {
		orderedPropertyToGenerateIndices.lazy.map { self.propertiesToGenerate[$0] }
	}

	/// The indices in `propertiesToGenerate` of `orderedPropertiesToGenerate`. Kept as indices so that
	/// `propertiesToGenerate` holds the only references this generator has to its children (see `deinit`). Worked out when
	/// the generator is created, from nothing but what it and its children hold from their creation, so that every walk of
	/// its tree, which reads it without awaiting the generator, shares one order.
	private let orderedPropertyToGenerateIndices: [Int]

	/// The order of the children, `orderedPropertyToGenerateIndices` where `startingCarriersLast`.
	/// - Parameter startingCarriersLast: Whether a child that holds a place starts after its siblings that hold none
	///   (`startsAsCarrier(_:)`), as the build does. `false` gives the inline build's order, declaration order with each
	///   child after the siblings it depends upon, in which a mock's `SafeDIOverrides` and each configuration take their
	///   members (`inlineOrdered(_:property:)`).
	nonisolated func computeOrderedPropertyToGenerateIndices(startingCarriersLast: Bool) -> [Int] {
		Self.orderedPropertyToGenerateIndices(
			of: propertiesToGenerate,
			receivedBuilderLoops: receivedBuilderLoops,
			requiredOnlyIfAvailableAliasProperties: requiredOnlyIfAvailableAliasProperties,
			placeHoldingProperties: placeHoldingProperties,
			startingCarriersLast: startingCarriersLast,
		)
	}

	/// `computeOrderedPropertyToGenerateIndices(startingCarriersLast:)` of a scope whose children are
	/// `propertiesToGenerate`, before the scope's generator exists.
	@inline(never)
	nonisolated private static func orderedPropertyToGenerateIndices(
		of propertiesToGenerate: [ScopeGenerator],
		receivedBuilderLoops: ReceivedBuilderLoops,
		requiredOnlyIfAvailableAliasProperties: Set<Property>,
		placeHoldingProperties: Set<Property>?,
		startingCarriersLast: Bool,
	) -> [Int] {
		func startsAsCarrier(_ child: ScopeGenerator) -> Bool {
			Self.startsAsCarrier(child, placeHoldingProperties: placeHoldingProperties)
		}
		// No child, or one, has no sibling to order against, and is generated whether or not it declares a property: most
		// scopes of a tree are leaves.
		guard propertiesToGenerate.count > 1 else { return Array(propertiesToGenerate.indices) }
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
		// another sibling declares that property itself. Where siblings of both wrapper kinds create one instance,
		// a by-value receive waits on each, since which one its binding reads is decided where the code is generated.
		var lazilyInstantiatedSiblingIndicesByInstanceProperty = [Property: [Int]]()
		for case let (instanceProperty?, index) in siblings.lazy.map({ ($0.instanceProperty, $0.index) })
			where siblingIndexByProperty[instanceProperty] == nil
		{
			lazilyInstantiatedSiblingIndicesByInstanceProperty[instanceProperty, default: []].append(index)
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
					} else if let siblingIndices = lazilyInstantiatedSiblingIndicesByInstanceProperty[property] {
						dependencies.formUnion(siblingIndices)
					}
				}
			} else {
				func isReceivedAndRequired(_ property: Property) -> Bool {
					scope.receivedProperties.contains(property) && isRequiredReceive(property)
				}
				for sibling in siblings
					where isReceivedAndRequired(sibling.property)
					|| sibling.instanceProperty.map({ siblingIndexByProperty[$0] == nil && isReceivedAndRequired($0) }) == true
				{
					dependencies.insert(sibling.index)
				}
			}
			// A required optional property resolves to a mock root's promoted sibling of its non-optional form, which the
			// mock promotes once for both forms.
			for property in scope.unwrappedOptionalRequiredReceivedProperties {
				if let siblingIndex = siblingIndexByProperty[property] {
					dependencies.insert(siblingIndex)
				} else if let siblingIndices = lazilyInstantiatedSiblingIndicesByInstanceProperty[property] {
					dependencies.formUnion(siblingIndices)
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

	/// The member calls `memberCallLines` writes, each a place of its own written as its line, which lists what the line
	/// reads, as a payload binding's place does (`valuesBindingPlaces`), so the type key lays them out as the first
	/// statements of the builder function's body and plans the function, rather than writing the tree around it per path.
	nonisolated private var memberCallPlaces: [GeneratedCode] {
		memberCallsInsideFunction.map { binding in
			let line = binding.line(readingInstancesOf: callSiteLazilyInstantiatedInstanceProperties)
			let record = AliasPlaceRecord(
				property: Property(label: binding.bindingName, typeDescription: binding.boundType),
				fulfillingProperty: nil,
				text: line,
				reads: binding.reads(readingInstancesOf: callSiteLazilyInstantiatedInstanceProperties),
			)
			return .indented(.place(PlacePlan(code: .text("\(line)\n"), record: .alias(record))), by: Self.standardIndent)
		}
	}

	/// How generated code spells the attributes of a local function it declares: `@inline(never)` in a seam’s tree
	/// (`LocalFunctionInlining`), then `@Sendable nonisolated` where the function is `@Sendable`. A `Sendable` wrapper calls
	/// its function synchronously from any isolation, so the function must be nonisolated, which is what Swift infers for a
	/// `@Sendable` local function in a module whose declarations default to no isolation. A module whose declarations default to the main actor
	/// (`-default-isolation MainActor`) infers the function to be on the main actor instead, and rejects it as `@Sendable`,
	/// so the spelling says `nonisolated` (`SafeDIToolDefaultMainActorIsolationTests`).
	static func localFunctionPrefix(isSendable: Bool) -> String {
		LocalFunctionInlining.attribute + (isSendable ? "@Sendable nonisolated " : "")
	}

	/// The lines that bind the payloads of the cases on the routes to the places beneath this scope, which its parent emits
	/// before its builder function, where the parent binds their labels: each field read as the parent's receivers read it.
	nonisolated private var valuesBindingLines: String {
		valuesBindings.map { "\($0.line(readingInstancesOf: callSiteLazilyInstantiatedInstanceProperties))\n" }.joined()
	}

	/// The payloads `valuesBindingLines` binds, each as an argument of the initializer of the class a boxed loop's box is
	/// (`boxedLoops`), labeled with its binding's name.
	/// A run struct of a carrier level's values (`SeamCarrierValues`) is bound before the box, where the members' arguments
	/// read it, and is not boxed: no builder function of the loop reads it, so unboxing it would bind a value nothing reads.
	nonisolated private var valuesBindingArguments: [String] {
		valuesBindings.filter { $0.formsRunAfter == nil }.map { binding in
			"\(binding.bindingName): \(binding.expression(readingInstancesOf: callSiteLazilyInstantiatedInstanceProperties))"
		}
	}

	/// The lines that bind the run structs the box's arguments read, before the box.
	nonisolated private var runStructBindingLinesBeforeBox: String {
		valuesBindings.filter { $0.formsRunAfter != nil }.map { "\($0.line(readingInstancesOf: callSiteLazilyInstantiatedInstanceProperties))\n" }.joined()
	}

	/// The lines at the top of a boxed loop member's builder function that unbox its own payloads under their names, so
	/// everything beneath reads them as it reads a payload bound before the function.
	nonisolated private func loopLevelsUnboxingLines(from loopLevelsName: String) -> [String] {
		valuesBindings.filter { $0.formsRunAfter == nil }.map { "\(Self.standardIndent)let \($0.bindingName) = \(loopLevelsName).\($0.bindingName)" }
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

	/// Whether the children at `childIndex` and `otherIndex` of `propertiesToGenerate` are members of one loop of builders
	/// (see `ReceivedBuilderLoops`).
	nonisolated func areMembersOfOneLoop(childAt childIndex: Int, _ otherIndex: Int) -> Bool {
		guard let loop = receivedBuilderLoops.loopByChildIndex[childIndex] else { return false }
		return receivedBuilderLoops.loopByChildIndex[otherIndex] == loop
	}

	/// The indices of the children on a loop of builders (see `ReceivedBuilderLoops`) whose wrapper nothing outside their
	/// loop reads: neither this scope's construction nor a generated child that is not on the loop. Only a mock root has any. A
	/// production scope's children are its type's own properties, which its construction reads, while a mock root's are
	/// also the properties it promotes, some only because the tree of a member of their loop receives them.
	// D1 lane hook (lane B): the mock lowering reads which loop members its level binds no wrapper of.
	/// `loopMembersReadOnlyInsideTheirLoop()`, read by the mock lowering.
	nonisolated var mockLoweringLoopMembersReadOnlyInsideTheirLoop: Set<Int> {
		Set(loopMembersReadOnlyInsideTheirLoop())
	}

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
		/// The child's index in `propertiesToGenerate`, which tells it apart from its siblings: two children of one scope can
		/// hold one generator (a construction memo can hand a place a generator a sibling holds).
		let index: Int
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

	/// The generators of the children, in `orderedPropertiesToGenerate`'s order, for a walk that reads no child's
	/// availability.
	nonisolated var orderedChildGenerators: [ScopeGenerator] {
		orderedPropertyToGenerateIndices.map { propertiesToGenerate[$0] }
	}

	// D1 lane hook (lane E): each child in generation order with its index in `propertiesToGenerate`, which keys a place
	// by its path of child indices.
	nonisolated var orderedChildGeneratorsWithIndices: [(index: Int, generator: ScopeGenerator)] {
		orderedPropertyToGenerateIndices.map { ($0, propertiesToGenerate[$0]) }
	}

	/// `orderedChildren(propertiesGeneratedLater:)`, with the indices of each property worked out afresh, for a walk of a
	/// seam's tree that reads what generation will emit without awaiting each generator.
	nonisolated func orderedChildrenComputedAfresh(propertiesGeneratedLater: Set<Property>) -> [OrderedChild] {
		let orderedIndices = orderedPropertyToGenerateIndices
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
		for (index, childIndex) in orderedIndices.enumerated() {
			let childGenerator = propertiesToGenerate[childIndex]
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
				index: childIndex,
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
		children: [some CycleParameterSearchNode],
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
			for (property, dependency) in receivesFromAbove(ofOwnDependencies: dependencies) {
				meet(property.label, receiver: .init(property: property, declarationLocation: dependency.declarationLocation, chain: chain(endingAt: index)))
			}
		}
		meet(ownDependencies, ofTypeAt: 0)
		// The scope visited next is the last one on the stack, so the first child goes last. Each is visited with the index
		// of the type it is built inside.
		var generatorsToVisit = children.reversed().map { (generator: $0, parentIndex: 0) }
		// A generator places share (`construction-memo.md`) is one subtree, which meets the same labels wherever the walk
		// reaches it: the labels it left unmet the first time stay unmet beneath it. So the walk visits each once, or it
		// would visit a loop of builders once per path to each member. The set is this walk's and dies with it.
		var visitedGenerators = Set<ObjectIdentifier>()
		while !unmetLabels.isEmpty, let (generator, parentIndex) = generatorsToVisit.popLast() {
			guard visitedGenerators.insert(generator.searchIdentity).inserted else { continue }
			// An alias is among the dependencies of the type that declares it, which the walk met first.
			var index = parentIndex
			if let builtInstantiable = generator.searchBuiltInstantiable {
				visitedTypes.append((builtInstantiable.concreteInstantiable, parentIndex))
				index = visitedTypes.count - 1
				meet(builtInstantiable.dependencies, ofTypeAt: index)
			}
			// A cycle-closing scope receives the parameters of the function it refers to, where that function's body does.
			for parameter in generator.searchCycleParameters where generator.searchClosesPropertyCycle {
				// This function's own parameter, whose receive this walk met where the scope was given the parameter: a chain
				// through the scope would grow with each pass that finds the parameters, which then never settle. A scope
				// closes on this function when it repeats its declaration, in either form: a lazily instantiated scope repeats a
				// constant declaration of its label and instance type, and a constant scope a lazily instantiated one, while
				// their properties differ. A scope of this function's property that closes on a function built for another
				// concrete type keeps the receiver it was given too; a chain through it would change only diagnostic text.
				meet(parameter.property.label, receiver: generator.searchProperty == builtProperty || generator.searchClosedOnDeclaration == builtDeclaration
					? parameter.receiver
					: .init(property: parameter.receiver.property, declarationLocation: parameter.receiver.declarationLocation, chain: chain(endingAt: parentIndex) + parameter.receiver.chain))
			}
			generatorsToVisit.append(contentsOf: generator.searchChildren.reversed().map { (generator: $0, parentIndex: index) })
		}
		return firstReceives
	}

	/// Whether this scope declares a builder function a lazy cycle closes on that takes parameters (see `CycleParameter`).
	nonisolated var declaresCycleParameters: Bool {
		!cycleParameters.isEmpty && !closesPropertyCycle
	}

	/// `declarationsByLabel`, the declarations a walk of omissions (see `OmissionFindings`) sees where this scope's builder
	/// function, `function`, is declared, as the function's body sees them: each parameter's label names the parameter.
	nonisolated private func bodyDeclarations(function: Int, enclosing declarationsByLabel: [String: [VisibleDeclaration]]) -> [String: [VisibleDeclaration]] {
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
	nonisolated private func bodyEnclosingCycleFunctions(function: Int, enclosing enclosingCycleFunctions: [BuiltDeclaration: Int]) -> [BuiltDeclaration: Int] {
		guard declaresCycleParameters, let declaration else { return enclosingCycleFunctions }
		var bodyEnclosingCycleFunctions = enclosingCycleFunctions
		bodyEnclosingCycleFunctions[declaration] = function
		return bodyEnclosingCycleFunctions
	}

	/// The forms the parameters of this scope's builder function provide to the function's body, or none when it takes
	/// no parameters a lazy cycle needs.
	/// The members of each child's loop of builders whose wrappers the `__safeDI_<label>_received` function the body
	/// declares for that child makes again for the parameters a lazy cycle needs, by the child's index, as
	/// `bodyChildren(propertiesGeneratedLater:enclosingFunctionNames:)` declares them: a member that takes such parameters
	/// is a loop's non-alias child with cycle parameters, and the members are the loop's non-alias children and the renames
	/// the body declares of them. Empty for nearly every body.
	///
	/// - Parameter includingChildrenWithoutCycleParameters: Whether to give the members of every non-alias child on a loop, also one whose
	///   function takes no such parameter: a call place of a plan by declaration (`VariantAnswers`) stands for a function
	///   that takes them, and has none of its own.
	nonisolated func loopMembersPassedByReceivedFunctions(of orderedChildren: [OrderedChild], includingChildrenWithoutCycleParameters: Bool = false) -> [Int: Set<Property>] {
		let loopByChildIndex = receivedBuilderLoops.loopByChildIndex
		guard !loopByChildIndex.isEmpty else { return [:] }
		var membersByLoop = [Int: Set<Property>]()
		for child in orderedChildren where !child.generator.isAlias {
			guard let property = child.generator.property, let loop = loopByChildIndex[child.index] else { continue }
			membersByLoop[loop, default: []].insert(property)
		}
		for child in orderedChildren where child.generator.isAlias {
			if case let .alias(property, fulfillingProperty, _, _, _) = child.generator.scopeData,
			   let loop = loopByChildIndex[child.index],
			   membersByLoop[loop, default: []].contains(fulfillingProperty)
			{
				membersByLoop[loop, default: []].insert(property)
			}
		}
		var membersByChildIndex = [Int: Set<Property>]()
		for child in orderedChildren where !child.generator.isAlias && (includingChildrenWithoutCycleParameters || !child.generator.cycleParameters.isEmpty) {
			guard let loop = loopByChildIndex[child.index] else { continue }
			membersByChildIndex[child.index] = membersByLoop[loop, default: []]
		}
		return membersByChildIndex
	}

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

	// D1 lane hook (lane B): the mock lowering orders a node's children as the emitter does, inside its builder function.
	/// `bodyPropertiesGeneratedLater(_:)`, read by the mock lowering.
	nonisolated func mockLoweringBodyPropertiesGeneratedLater(_ propertiesGeneratedLater: Set<Property>) -> Set<Property> {
		bodyPropertiesGeneratedLater(propertiesGeneratedLater)
	}

	// D1 lane hook (lane B): the mock lowering builds a node's construction inside its builder function, where its cycle
	// parameters and rebound properties are bound, as the emitter does.
	/// `bodyUnavailableProperties(_:)`, read by the mock lowering.
	nonisolated func mockLoweringBodyUnavailableProperties(_ unavailableProperties: Set<Property>) -> Set<Property> {
		bodyUnavailableProperties(unavailableProperties)
	}

	// D1 lane hook (lane B): the mock lowering names a level's builder functions apart from the enclosing functions its
	// cycle-closing nodes refer to, as the mock emitter does (`generateMockBodyBindings`).
	/// The name of the builder function of each of `generators`, one level of a mock's tree whose property nodes are bound
	/// as `bindingNames` says, where `builderFunctionNames(for:enclosingFunctionNames:)` renames it, else `nil`; or `nil`
	/// where no property node of the level takes part in a cycle, as the emitter skips such a level. A site of a hole held in
	/// a wrapper is named among them after the property nodes, as the emitter names it. `enclosingFunctionNames` is asked
	/// only for a level that takes part in a cycle.
	nonisolated static func mockLoweringBuilderFunctionNames(
		of generators: [ScopeGenerator],
		boundAs bindingNames: [String?],
		enclosingFunctionNames: () -> [BuiltDeclaration: String],
	) -> [String?]? {
		// A level renames a function only where a node on it closes a cycle or is closed on, which nearly no level has.
		guard generators.contains(where: { !$0.cycleClosedOnDeclarations.isEmpty || $0.isReferencedByCycleClosingScope }) else { return nil }
		var candidates = [BuilderFunctionCandidate]()
		var generatorIndices = [Int]()
		for (index, generator) in generators.enumerated() {
			guard case let .property(_, property, _, _, isPropertyCycle, _) = generator.scopeData, let declaration = generator.declaration else { continue }
			let bindingName = index < bindingNames.count ? bindingNames[index] : nil
			candidates.append(BuilderFunctionCandidate(
				property: property,
				declaration: declaration,
				name: bindingName.flatMap { $0 == property.label ? nil : functionName(toBuildPropertyNamed: $0) },
				declaresFunction: !isPropertyCycle,
				cycleClosedOnDeclarations: generator.cycleClosedOnDeclarations,
				isReferencedByCycleClosingScope: generator.isReferencedByCycleClosingScope,
				referencedFillNames: Set(generator.referencedFillNamesByKey.values),
			))
			generatorIndices.append(index)
		}
		// A site of a hole held in a wrapper declares the function the wrapper is built around, named after the level's
		// properties' functions, as the emitter's `holeSitesBuildingWrappers` are.
		for (index, generator) in generators.enumerated() {
			guard case let .hole(property, _, site) = generator.scopeData, site != nil, !property.propertyType.isConstant else { continue }
			candidates.append(BuilderFunctionCandidate(
				property: property,
				declaration: BuiltDeclaration(property: property, concreteType: property.typeDescription.asInstantiatedType),
				name: generator.holeWrapperFunctionName,
				declaresFunction: true,
				cycleClosedOnDeclarations: [],
				isReferencedByCycleClosingScope: false,
				referencedFillNames: [],
			))
			generatorIndices.append(index)
		}
		guard candidates.contains(where: { !$0.cycleClosedOnDeclarations.isEmpty || $0.isReferencedByCycleClosingScope }) else { return nil }
		var names = [String?](repeating: nil, count: generators.count)
		for (candidateIndex, builderFunctionNames) in builderFunctionNames(for: candidates, enclosingFunctionNames: enclosingFunctionNames()).enumerated() {
			names[generatorIndices[candidateIndex]] = builderFunctionNames.functionName
		}
		return names
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

	/// What `cycleParameterArguments(unavailableProperties:)` passes, each with the parameter it passes, for the type key.
	nonisolated private func cycleParameterReads(unavailableProperties: Set<Property>) -> [PlaceRead] {
		cycleParameters.map { parameter in
			let label = parameter.property.label
			let source: ArgumentSource = if unavailableProperties.contains(parameter.property) {
				.nil
			} else if let instanceSource = callSiteLazilyInstantiatedInstanceProperties.lazilyInstantiatedInstanceSource(of: parameter.property, boundAs: label) {
				instanceSource
			} else {
				.binding(label: label)
			}
			return PlaceRead(argumentLabel: label, label: label, property: parameter.property, source: source)
		}
	}

	/// What the construction of `instantiable` in this scope's builder function reads, for the type key, or `nil` where it is
	/// constructed with anything but its initializer's arguments. It throws what the path key's construction
	/// (`constructionArgumentList(of:unavailableProperties:propertiesGeneratedLater:holeBuilders:)`), which makes the same call first, throws.
	nonisolated private func constructionReads(of instantiable: Instantiable, unavailableProperties: Set<Property>) throws(Initializer.GenerationError) -> [PlaceRead]? {
		guard builderCallArguments.isEmpty else { return nil }
		return try initializerArgumentReads(of: instantiable, unavailableProperties: unavailableProperties)
	}

	/// What the construction of `instantiable` reads through its initializer's arguments, whatever builders the call passes
	/// after them, or `nil` where it is constructed with anything but its initializer.
	nonisolated private func initializerArgumentReads(of instantiable: Instantiable, unavailableProperties: Set<Property>) throws(Initializer.GenerationError) -> [PlaceRead]? {
		guard publicMockCall == nil, !constructsWithHandWrittenMock, let initializer = instantiable.initializer else { return nil }
		let arguments = try initializer.createInitializerArguments(
			given: instantiable.dependencies,
			unavailableProperties: bodyUnavailableProperties(unavailableProperties),
			lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties,
		)
		return arguments.map {
			PlaceRead(argumentLabel: $0.argument.label, label: $0.dependency.property.label, property: $0.dependency.property, source: $0.argument.source)
		}
	}

	/// Where a test observes seam calls (`SeamCallRecordObservation`) and this scope's call of another module's seam fills
	/// a builder, the call's record as the engine is to spell it, handed to the test beside its text: a built place whose
	/// call fields pass each builder up or build it (`BuiltClosure`). A call that re-enters an enclosing call's dispatcher, a
	/// call of a public mock, a member of a loop of builders and a member of a cycle are not observed yet.
	nonisolated private func observeFilledCall(
		of property: Property,
		instantiable: Instantiable,
		seamCall: SeamCall,
		erasedToConcreteExistential: Bool,
		code: GeneratedCode,
		unavailableProperties: Set<Property>,
		builderFunctionNames: BuilderFunctionNames,
		inlinePlaceBuilder: FillPlaceBindings.HoleBuilder?,
	) throws(Initializer.GenerationError) {
		guard let observer = SeamCallRecordObservation.observer,
		      publicMockCall == nil,
		      reboundProperties.isEmpty,
		      cycleParameters.isEmpty,
		      inlinePlaceBuilder == nil,
		      builderCallArguments.contains(where: { $0.builtCall != nil }),
		      builderCallArguments.allSatisfy({ $0.builtCall != nil || $0.passedUpStruct != nil }),
		      let argumentReads = try initializerArgumentReads(of: instantiable, unavailableProperties: unavailableProperties)
		else { return }
		var closureArguments = [ClosureArgumentEntry]()
		var builtClosures = [BuiltClosure]()
		var spelledArguments = [String]()
		for (builder, builderCallArgument) in zip(seamCall.calledBuilders.builders, builderCallArguments) {
			if let passedUpStruct = builderCallArgument.passedUpStruct {
				let read = PassedOnRead(calledType: instantiable.concreteInstantiable, builderLabel: builder.label, structType: passedUpStruct.type, caseName: passedUpStruct.caseName, member: passedUpStruct.member)
				closureArguments.append(ClosureArgumentEntry(label: builderCallArgument.label, value: .passedOn(read)))
				spelledArguments.append("\(builderCallArgument.label): \(read.member.spelled(on: passedUpStruct.name, caseName: read.caseName))")
			} else if let builtCall = builderCallArgument.builtCall {
				let builtClosure = BuiltClosure(
					rootDispatcherKey: builtCall.dispatcherKey,
					dispatchers: [],
					fillChildIndices: [],
					carriedStructs: builtCall.carriedStructs.map { BuiltClosure.CarriedStructRead(upName: $0.upName, structType: $0.type) },
				)
				closureArguments.append(ClosureArgumentEntry(label: builderCallArgument.label, value: .built(BuiltClosureID(builtClosures.count))))
				builtClosures.append(builtClosure)
				spelledArguments.append("\(builderCallArgument.label): \(builtClosure.spelled(dispatcherName: builtCall.dispatcherName, structNames: builtCall.carriedStructs.map(\.name)))")
			}
		}
		let (text, _) = code.spelledWithoutRootFunctions()
		var record = BuiltPlaceRecord(
			property: property,
			isErased: erasedToConcreteExistential,
			concreteType: instantiable.concreteInstantiable,
			isExtension: false,
			target: .initializer(instantiable.concreteInstantiable),
			arguments: argumentReads,
			forwardedProperties: [],
			cycleParameters: [],
			callCycleArguments: [],
			functionName: builderFunctionNames.functionName ?? Self.functionName(toBuild: property),
			isSendable: buildsInSendableFunction,
			typesDeclaredEscaping: typesDeclaredEscaping,
			lineEnd: "",
			hasFunction: true,
			children: [],
			node: PlanNode(),
		)
		record.callFields = CallFields(
			leadingStatement: seamCall.callGuard(for: instantiable.concreteInstantiable),
			closureArguments: closureArguments,
			builtClosures: builtClosures,
		)
		observer(SeamCallRecordObservation(
			text: text,
			// The text declares the call's dispatchers and fills, whose names and reads the record does not hold yet.
			readNames: nil,
			boundNames: nil,
			spelledFromRecord: (record.leadingStatement.map { [$0.spelled] } ?? []) + spelledArguments,
			written: [seamCall.guardLine(for: instantiable.concreteInstantiable)] + builderCallArguments.map { "\($0.label): \($0.value)" },
		))
	}

	/// The record of this scope's place where it calls another module's seam and is built by value: its text, with the reads
	/// of the call's arguments, or `nil` where the type key does not plan it. Where a test observes it
	/// (`SeamCallRecordObservation`), the place's record as the engine is to spell it is handed to the test beside its text.
	/// A builder's forwarded values are bound inside its text, so a read of one of `forwardedProperties`' labels is no read
	/// outside it; only a call that forwards nothing is observed or spelled by the engine in place.
	nonisolated private func seamCallRecord(
		of property: Property,
		instantiable: Instantiable,
		seamCall: SeamCall,
		erasedToConcreteExistential: Bool,
		forwardedProperties: [Property] = [],
		code: GeneratedCode,
		declaredFunctionName: String?,
		unavailableProperties: Set<Property>,
		builderFunctionNames: BuilderFunctionNames,
		fillPlaceBindings: FillPlaceBindings,
		inlinePlaceBuilder: FillPlaceBindings.HoleBuilder?,
		separatesValuesBindings: Bool,
		inPlaceStatements: (before: [GeneratedCode], after: [GeneratedCode])?,
		lineEnd: String,
	) throws(Initializer.GenerationError) -> PlaceRecord? {
		if SeamCallRecordObservation.observer != nil, forwardedProperties.isEmpty {
			try observeFilledCall(of: property, instantiable: instantiable, seamCall: seamCall, erasedToConcreteExistential: erasedToConcreteExistential, code: code, unavailableProperties: unavailableProperties, builderFunctionNames: builderFunctionNames, inlinePlaceBuilder: inlinePlaceBuilder)
		}
		guard isPlannedByTypeKey(builderFunctionNames: builderFunctionNames, fillPlaceBindings: fillPlaceBindings, separatesValuesBindings: separatesValuesBindings),
		      inlinePlaceBuilder == nil,
		      cycleParameters.isEmpty,
		      let argumentReads = try initializerArgumentReads(of: instantiable, unavailableProperties: unavailableProperties)
		else { return nil }
		var reads = argumentReads
		let forwardedLabels = Set(forwardedProperties.map(\.label))
		reads.removeAll { forwardedLabels.contains($0.label) }
		// A call that passes places up hands the seam a member of the builder or level the caller's tree holds for each: a read
		// of that struct, typed as the caller's tree binds it. A call that fills a place, or passes a struct no binding of the
		// tree types, such as one a fill is handed, is not planned.
		for builderCallArgument in builderCallArguments {
			guard let passedUpStruct = builderCallArgument.passedUpStruct else { return nil }
			guard !reads.contains(where: { $0.label == passedUpStruct.name }) else { continue }
			reads.append(PlaceRead(
				argumentLabel: passedUpStruct.name,
				label: passedUpStruct.name,
				property: Property(label: passedUpStruct.name, typeDescription: passedUpStruct.type),
				source: .binding(label: passedUpStruct.name),
				// SafeDI cannot tell the struct is `Sendable`, as for a hole site's read of it.
				staysOutsideSendableFunctions: true,
			))
		}
		// The root declares the root functions the call reaches, which its text leaves out.
		let (text, rootFunctionNames) = code.spelledWithoutRootFunctions()
		// A member of a loop of builders makes its rebindings again in the call's body, which the loop stage records.
		if let observer = SeamCallRecordObservation.observer, reboundProperties.isEmpty, forwardedProperties.isEmpty {
			// Every builder argument passes a struct up (the guard above), in the order the seam's builders are taken.
			let passedOn = zip(seamCall.calledBuilders.builders, builderCallArguments).compactMap { builder, builderCallArgument in
				builderCallArgument.passedUpStruct.map { passedUpStruct in
					(
						label: builderCallArgument.label,
						read: PassedOnRead(calledType: instantiable.concreteInstantiable, builderLabel: builder.label, structType: passedUpStruct.type, caseName: passedUpStruct.caseName, member: passedUpStruct.member),
						structName: passedUpStruct.name,
						written: "\(builderCallArgument.label): \(builderCallArgument.value)",
					)
				}
			}
			var record = BuiltPlaceRecord(
				property: property,
				isErased: erasedToConcreteExistential,
				concreteType: instantiable.concreteInstantiable,
				isExtension: false,
				target: .initializer(instantiable.concreteInstantiable),
				arguments: argumentReads,
				forwardedProperties: [],
				cycleParameters: [],
				callCycleArguments: [],
				functionName: builderFunctionNames.functionName ?? Self.functionName(toBuild: property),
				isSendable: buildsInSendableFunction,
				typesDeclaredEscaping: typesDeclaredEscaping,
				lineEnd: "",
				// The guard line is a statement, so every call declares its builder function.
				hasFunction: true,
				children: [],
				node: PlanNode(),
			)
			record.callFields = CallFields(
				leadingStatement: seamCall.callGuard(for: instantiable.concreteInstantiable),
				closureArguments: passedOn.map { ClosureArgumentEntry(label: $0.label, value: .passedOn($0.read)) },
			)
			observer(SeamCallRecordObservation(
				text: text,
				readNames: record.arguments.filter { $0.source != .nil }.map(\.label) + passedOn.map(\.structName),
				boundNames: [property.label] + (declaredFunctionName.map { [$0] } ?? []),
				spelledFromRecord: (record.leadingStatement.map { [$0.spelled] } ?? []) + passedOn.map { "\($0.label): \($0.read.member.spelled(on: $0.structName, caseName: $0.read.caseName))" },
				written: [seamCall.guardLine(for: instantiable.concreteInstantiable)] + passedOn.map(\.written),
			))
		}
		var record = AliasPlaceRecord(property: property, fulfillingProperty: nil, text: text, reads: reads)
		record.declaredFunctionNames = declaredFunctionName.map { [$0] } ?? []
		record.calledRootFunctionNames = rootFunctionNames
		// A call that reaches no root function, outside a loop of builders, is spelled by the engine from its record where
		// its text is written: the guard line, and a construction that hands each builder the member of the struct it
		// passes up.
		if let inPlaceStatements, rootFunctionNames.isEmpty, reboundProperties.isEmpty, forwardedProperties.isEmpty, let declaredFunctionName {
			var arguments = argumentReads
			var argumentValues = [Int: ValuePath]()
			var closureArguments = [ClosureArgumentEntry]()
			// Every builder argument passes a struct up (the guard above), in the order the seam's builders are taken.
			let passedUpStructs = zip(seamCall.calledBuilders.builders, builderCallArguments).compactMap { builder, builderCallArgument in
				builderCallArgument.passedUpStruct.map { (builder: builder, label: builderCallArgument.label, passedUpStruct: $0) }
			}
			for (builder, label, passedUpStruct) in passedUpStructs {
				let structRead = PlaceRead(
					argumentLabel: label,
					label: passedUpStruct.name,
					property: Property(label: passedUpStruct.name, typeDescription: passedUpStruct.type),
					source: .binding(label: passedUpStruct.name),
					// SafeDI cannot tell the struct is `Sendable`, as for a hole site's read of it.
					staysOutsideSendableFunctions: true,
				)
				let passedOnRead = PassedOnRead(calledType: instantiable.concreteInstantiable, builderLabel: builder.label, structType: passedUpStruct.type, caseName: passedUpStruct.caseName, member: passedUpStruct.member)
				argumentValues[arguments.count] = passedOnRead.member.value(reading: structRead, caseName: passedOnRead.caseName)
				arguments.append(structRead)
				closureArguments.append(ClosureArgumentEntry(label: label, value: .passedOn(passedOnRead)))
			}
			var callRecord = BuiltPlaceRecord(
				property: property,
				isErased: erasedToConcreteExistential,
				concreteType: instantiable.concreteInstantiable,
				isExtension: instantiable.declarationType.isExtension,
				target: .initializer(instantiable.concreteInstantiable),
				arguments: arguments,
				forwardedProperties: [],
				cycleParameters: [],
				callCycleArguments: [],
				functionName: declaredFunctionName,
				isSendable: buildsInSendableFunction,
				typesDeclaredEscaping: typesDeclaredEscaping,
				lineEnd: lineEnd,
				hasFunction: true,
				children: [],
				node: PlanNode(),
			)
			if !argumentValues.isEmpty {
				callRecord.argumentValues = argumentValues
			}
			callRecord.callFields = CallFields(
				leadingStatement: seamCall.callGuard(for: instantiable.concreteInstantiable),
				closureArguments: closureArguments,
			)
			record.call = InPlaceCall(
				record: callRecord,
				statementsBeforeLeadingStatement: inPlaceStatements.before,
				statementsAfterLeadingStatement: inPlaceStatements.after,
			)
		}
		return .alias(record)
	}

	/// The record of this scope's place where it closes a cycle on the function named `closedOnFunctionName`, or `nil` where
	/// the type key does not plan it.
	nonisolated private func closingRecord(
		of property: Property,
		instantiable: Instantiable,
		forwardedProperties: [Property],
		erasedToConcreteExistential: Bool,
		closedOnFunctionName: String,
		unavailableProperties: Set<Property>,
		builderFunctionNames: BuilderFunctionNames,
		fillPlaceBindings: FillPlaceBindings,
	) -> PlaceRecord? {
		guard isPlannedByTypeKey(builderFunctionNames: builderFunctionNames, fillPlaceBindings: fillPlaceBindings) else { return nil }
		return .closer(ClosingPlaceRecord(
			property: property,
			isErased: erasedToConcreteExistential,
			isExtension: instantiable.declarationType.isExtension,
			closedOnFunctionName: closedOnFunctionName,
			forwardedProperties: forwardedProperties,
			cycleArguments: cycleParameterReads(unavailableProperties: unavailableProperties),
		))
	}

	/// Whether this scope's place is written with nothing the type key does not plan: no payload, loop or fill binding, no
	/// seam call, and no member call, but where the payloads or the member calls are places of their own
	/// (`separatesValuesBindings`, `separatesMemberCalls`).
	nonisolated private func isPlannedByTypeKey(builderFunctionNames: BuilderFunctionNames, fillPlaceBindings: FillPlaceBindings, separatesValuesBindings: Bool = false, separatesMemberCalls: Bool = false) -> Bool {
		(valuesBindingLines.isEmpty || separatesValuesBindings)
			&& builderFunctionNames.loopValuesBindingLines?.isEmpty != false
			&& builderFunctionNames.loopLevelsName == nil
			&& builderFunctionNames.receivedFunctionName == nil
			&& rebindingsArePlannedByTypeKey(builderFunctionNames: builderFunctionNames)
			&& (memberCallLines.isEmpty || separatesMemberCalls)
			&& !isBuiltByFill
			&& !fillReturnsWrapperBuilder
			&& fillPlaceBindings.bindingsByGenerator[ObjectIdentifier(self), default: []].isEmpty
	}

	/// Whether every rebinding this scope's builder function begins with, as a member of a loop of builders, is a place the
	/// type key lays out: a wrapper made again of a member's own builder function (`LoopRebinding.closer`), never one of a
	/// `__safeDI_<label>_received` function, of a rename, or of the function's own property with its cycle parameters.
	nonisolated private func rebindingsArePlannedByTypeKey(builderFunctionNames: BuilderFunctionNames) -> Bool {
		reboundProperties.allSatisfy { reboundProperty in
			!(reboundProperty == property && declaresCycleParameters)
				&& builderFunctionNames.loopMemberDeclarations[reboundProperty]?.closer != nil
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
		if ConcurrentChildCode.plansChildrenAtOnce {
			try await appendConcurrentChildCode(to: &body, codeGeneration: codeGeneration, leadingMemberWhitespace: leadingMemberWhitespace, fillPlaceBindings: fillPlaceBindings)
		} else {
			// One child after another, each awaited in this frame: a function between the body and each child's code
			// would add its frame to every task that plans a body (`.claude/rules/generator-design.md`).
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
		}
		return statements(of: consume body, leadingMemberWhitespace: leadingMemberWhitespace)
	}

	/// What a body asks of one child's code: the child's generator, which is an actor of its own, and the context the body
	/// decided for it before awaiting any child's code. A child's context never depends on another child's code.
	private struct ChildCodeRequest: Sendable {
		/// The child's position among the body's ordered children.
		let index: Int
		let generator: ScopeGenerator
		let unavailableProperties: Set<Property>
		let propertiesGeneratedLater: Set<Property>
		let builderFunctionNames: BuilderFunctionNames
	}

	/// The code of each of `requests`, in their order. A root of the dependency tree plans each of its body's children on a
	/// task of its own, at most `ConcurrentChildCode.maximumChildrenAtOnce` at a time, and the code comes back in the body's
	/// order of its children, never in the order the tasks finish. Beneath those children, and in every other tree, a body
	/// plans one child after another. A child's error is thrown as the roots' task group throws one
	/// (`DependencyTreeGenerator.plannedCode(of:rootsOfOtherModules:)`).
	private func appendConcurrentChildCode(
		to body: inout BodyChildren,
		codeGeneration: CodeGeneration,
		leadingMemberWhitespace: String,
		fillPlaceBindings: FillPlaceBindings,
	) async throws {
		let requests = body.orderedChildren.indices.filter { body.orderedChildren[$0].generator.fillEmitsCode }.map { index in
			ChildCodeRequest(
				index: index,
				generator: body.orderedChildren[index].generator,
				unavailableProperties: body.orderedChildren[index].unavailableProperties,
				propertiesGeneratedLater: body.orderedChildren[index].propertiesGeneratedLater,
				builderFunctionNames: builderFunctionNamesOfChild(at: index, in: body),
			)
		}
		for childCode in try await Self.concurrentChildCode(of: requests, codeGeneration: codeGeneration, leadingWhitespace: leadingMemberWhitespace, fillPlaceBindings: fillPlaceBindings) {
			append(childCode.code, ofChildAt: childCode.index, to: &body, leadingMemberWhitespace: leadingMemberWhitespace, fillPlaceBindings: fillPlaceBindings)
		}
	}

	/// The code of one of a body's children, under the child's position among the body's ordered children. Each child's
	/// task returns its code with its own position, so the body writes each code at the child it is for, whatever order
	/// the tasks finish in. A struct, never a tuple (`taskGroupTupleElement` in `.claude/rules/source-rules.md`).
	private struct ChildCode: Sendable {
		/// The child's position among the body's ordered children (`ChildCodeRequest.index`).
		let index: Int
		let code: GeneratedCode
	}

	/// The code of each of `requests`, in their order, each on a task of its own (`appendConcurrentChildCode`).
	private static func concurrentChildCode(
		of requests: [ChildCodeRequest],
		codeGeneration: CodeGeneration,
		leadingWhitespace: String,
		fillPlaceBindings: FillPlaceBindings,
	) async throws -> [ChildCode] {
		guard requests.count > 1 else {
			var childCodes = [ChildCode]()
			for request in requests {
				try await childCodes.append(ChildCode(
					index: request.index,
					code: request.generator.generateCode(
						codeGeneration: codeGeneration,
						unavailableProperties: request.unavailableProperties,
						propertiesGeneratedLater: request.propertiesGeneratedLater,
						builderFunctionNames: request.builderFunctionNames,
						leadingWhitespace: leadingWhitespace,
						fillPlaceBindings: fillPlaceBindings,
					),
				))
			}
			return childCodes
		}
		ConcurrentChildCode.record(childCount: requests.count)
		let maximumChildrenAtOnce = ConcurrentChildCode.maximumChildrenAtOnce
		let childCodesInFinishingOrder = try await withThrowingTaskGroup(
			of: ChildCode.self,
			returning: [ChildCode].self,
		) { taskGroup in
			var childCodes = [ChildCode]()
			childCodes.reserveCapacity(requests.count)
			for (position, request) in requests.enumerated() {
				// A child that waits for a task to finish holds no frame, so the children planned at once never hold more memory
				// than `maximumChildrenAtOnce` plans do.
				if position >= maximumChildrenAtOnce, let childCode = try await taskGroup.next() {
					childCodes.append(childCode)
				}
				taskGroup.addTask {
					// The child's own body plans its children one after another: planning every body's children at once
					// costs more processor time than it saves.
					let code = try await ConcurrentChildCode.$plansChildrenAtOnce.withValue(false) {
						try await request.generator.generateCode(
							codeGeneration: codeGeneration,
							unavailableProperties: request.unavailableProperties,
							propertiesGeneratedLater: request.propertiesGeneratedLater,
							builderFunctionNames: request.builderFunctionNames,
							leadingWhitespace: leadingWhitespace,
							fillPlaceBindings: fillPlaceBindings,
						)
					}
					if let ordering = ConcurrentChildCode.ordering {
						await ordering.waitForTurn(ofChildAt: position, childCount: requests.count)
					}
					return ChildCode(index: request.index, code: code)
				}
			}
			for try await childCode in taskGroup {
				childCodes.append(childCode)
			}
			return childCodes
		}
		// The tasks finish in any order: each child's code is put back at its own position.
		return childCodesInFinishingOrder.sorted { $0.index < $1.index }
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
		let loopMemberDeclarationsByLoop: [Int: [Property: LoopRebinding]]
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
		let callerArgumentByParameter: [Property: ArgumentSource]
		let callerMemoArgumentByMemo: [Property: ArgumentSource]
		/// The dispatchers of a seam's caller; empty for a public mock's caller, which declares level functions instead.
		let callDispatchers: [FillDispatcher]
		/// Which fills a dispatcher may hold in its case.
		let fillInlining: FillInlining
		/// The children's statements so far, in order, but for the fills a dispatcher holds.
		var generatedProperties = [GeneratedCode]()
		/// The bodies of the fills a dispatcher holds, by fill.
		var inlinedFills = [String: FillDispatcher.InlinedFill]()
		/// The keys of `inlinedFills` whose tree reads a value neither its case's payload nor its parameters hand it: a
		/// declaration around the call, which the dispatcher holding the fill captures.
		var inlinedFillKeysReadingCallersDeclarations = Set<String>()
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
		var loopMemberDeclarationsByLoop = [Int: [Property: LoopRebinding]]()
		var receivedFunctionNameByIndex = [Int: String]()
		var memberFunctionByProperty = [Property: (property: Property, generator: ScopeGenerator, functionName: String)]()
		// The payloads of each loop's members, in the order the body generates them, and the index of the member that binds
		// them all: the loop's first. A boxed loop (`boxedLoops`) binds them in its box, named in `loopLevelsNameByLoop`.
		var valuesBindingLinesByLoop = [Int: String]()
		var valuesBindingMemberIndexByLoop = [Int: Int]()
		var boxedArgumentsByLoop = [Int: [String]]()
		var runStructLinesByLoop = [Int: String]()
		var loopLevelsNameByLoop = [Int: String]()
		if !receivedBuilderLoops.loopByChildIndex.isEmpty {
			// A child is told apart from its siblings by its index, never by its generator, which a sibling can hold too.
			let loopByChildIndex = receivedBuilderLoops.loopByChildIndex
			for (index, child) in orderedChildren.enumerated() where !child.generator.isAlias {
				guard let loop = loopByChildIndex[child.index] else { continue }
				if boxedLoops[loop] != nil {
					boxedArgumentsByLoop[loop, default: []] += child.generator.valuesBindingArguments
					runStructLinesByLoop[loop, default: ""] += child.generator.runStructBindingLinesBeforeBox
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
				loopMembers: orderedChildren.compactMap { loopByChildIndex[$0.index] == nil ? nil : $0.generator },
				enclosingFunctionNames: enclosingFunctionNames,
			))
			for (index, child) in orderedChildren.enumerated() where !child.generator.isAlias {
				guard let property = child.generator.property, let loop = loopByChildIndex[child.index] else { continue }
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
					valuesBindingLinesByLoop[loop] = runStructLinesByLoop[loop, default: ""] + Self.loopLevelsBinding(named: loopLevelsName, ofType: box.typeName, arguments: box.arguments)
				}
				if let receivedFunctionName = claimedNames.receivedFunctionName {
					functionName = receivedFunctionName
					receivedFunctionNameByIndex[index] = functionName
				}
				// A rebinding that hands the member's own builder function is a cycle-closing place on that function, which
				// the type key lays out (`LoopRebinding.closedOnFunctionName`); one that hands a `_received` function is not.
				loopMemberDeclarationsByLoop[loop, default: [:]][property] = child.generator.loopRebinding(
					functionName: functionName,
					closesOnFunction: claimedNames.receivedFunctionName == nil,
				)
				memberFunctionByProperty[property] = (property, child.generator, functionName)
			}
			// A rename this body declares of a member is rebound under its own label, wrapping the member's function.
			for child in orderedChildren where child.generator.isAlias {
				guard case let .alias(property, fulfillingProperty, _, _, _) = child.generator.scopeData,
				      let loop = loopByChildIndex[child.index],
				      let memberFunction = memberFunctionByProperty[fulfillingProperty],
				      let declaration = child.generator.loopRebindingDeclaration(ofRenameOf: memberFunction)
				else { continue }
				loopMemberDeclarationsByLoop[loop, default: [:]][property] = LoopRebinding(declaration: declaration, closer: nil)
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
		var callerArgumentByParameter = [Property: ArgumentSource]()
		var callerMemoArgumentByMemo = [Property: ArgumentSource]()
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
							callerArgumentByParameter[parameter] = .nil
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
		if !body.loopMemberDeclarationsByLoop.isEmpty, let loop = receivedBuilderLoops.loopByChildIndex[child.index] {
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
			// A fill reads a field bound from a deferred parameter from the caller's scope, not from what it is handed
			// (`fillBoundFields`), so such a read captures the caller's declaration.
			let handedLabels = Set((child.generator.fillBoundFields + (body.parametersByKey[key] ?? [])).map(\.property.label))
			if !child.generator.receivedProperties.allSatisfy({ handedLabels.contains($0.label) }) {
				body.inlinedFillKeysReadingCallersDeclarations.insert(key)
			}
		} else {
			body.generatedProperties.append(code)
		}
	}

	/// The keys of `dispatchers`, a seam call's, whose text captures nothing of the code around the call, so the root may
	/// declare them once for every call: each that hands no target the caller's declaration (`FillCallerReads`; those are
	/// `capturingKeys`), and whose every case is handed to a fill `inlinedFills` holds or to such a dispatcher of the call,
	/// with no struct of an enclosing call's level to hand on.
	nonisolated private static func rootFunctionDispatcherKeys(of dispatchers: [FillDispatcher], inlinedFills: [String: FillDispatcher.InlinedFill], capturingCallerDeclarations capturingKeys: Set<String>) -> Set<String> {
		var keys = Set(dispatchers.filter { !$0.takesPassUp && $0.carriedInnerScopes.isEmpty && !capturingKeys.contains($0.key) }.map(\.key))
		var changed = true
		while changed {
			changed = false
			for dispatcher in dispatchers where keys.contains(dispatcher.key) {
				let capturesNothing = dispatcher.cases.allSatisfy { dispatcherCase in
					guard let target = dispatcherCase.target else { return false }
					return target.reusedCarriedInnerScopes.isEmpty && (inlinedFills[target.key] != nil || keys.contains(target.key))
				}
				if !capturesNothing {
					keys.remove(dispatcher.key)
					changed = true
				}
			}
		}
		return keys
	}

	/// The statements of `body`, its children's code followed by the declarations of its call's dispatchers or a public
	/// mock's level functions.
	@inline(never)
	private func statements(of body: consuming BodyChildren, leadingMemberWhitespace: String) -> [GeneratedCode] {
		// Moved out of `body`, so that appending to it does not copy it.
		var generatedProperties = [GeneratedCode]()
		swap(&generatedProperties, &body.generatedProperties)
		// A call's dispatchers follow its fills, each a function that returns its level's struct. One that captures nothing
		// of the call is a root function, which the root may declare once for every call (`RootFunctionHoisting`).
		let labelsHiddenByReenteringCalls = Set(fillDeferredLabelsHiddenByReenteringCalls.values.joined())
		let callerArgumentByParameter = body.callerArgumentByParameter.mapValues(\.spelled)
		let callerMemoArgumentByMemo = body.callerMemoArgumentByMemo.mapValues(\.spelled)
		// A dispatcher captures the caller's declarations where it hands a target one (the root dispatcher, which takes no
		// parameter): its text then differs from the text written without them, which a root function's record holds. Every
		// other dispatcher of the call takes what its targets read as parameters, so the root may still declare it once.
		var capturingKeys = Set<String>()
		if !body.callerArgumentByParameter.isEmpty || !body.callerMemoArgumentByMemo.isEmpty {
			for dispatcher in body.callDispatchers {
				let withCallerDeclarations = dispatcher.declaration(isSendable: false, indent: "", inlinedFills: body.inlinedFills, parametersByKey: body.parametersByKey, callerArgumentByParameter: callerArgumentByParameter, callerMemoArgumentByMemo: callerMemoArgumentByMemo, typesDeclaredEscaping: typesDeclaredEscaping, fillsTakingPayloadFields: body.fillsTakingPayloadFields, labelsHiddenByReenteringCalls: labelsHiddenByReenteringCalls)
				let withoutCallerDeclarations = dispatcher.declaration(isSendable: false, indent: "", inlinedFills: body.inlinedFills, parametersByKey: body.parametersByKey, typesDeclaredEscaping: typesDeclaredEscaping, fillsTakingPayloadFields: body.fillsTakingPayloadFields, labelsHiddenByReenteringCalls: labelsHiddenByReenteringCalls)
				if withCallerDeclarations != withoutCallerDeclarations {
					capturingKeys.insert(dispatcher.key)
				}
			}
		}
		let rootFunctionKeys = Self.rootFunctionDispatcherKeys(of: body.callDispatchers, inlinedFills: body.inlinedFills.filter { !body.inlinedFillKeysReadingCallersDeclarations.contains($0.key) }, capturingCallerDeclarations: capturingKeys)
		// Where a test observes them, each dispatcher's declaration is spelled again from the call's records alone, beside
		// the text written here.
		let dispatcherObserver = DispatcherRecordObservation.observer
		let filledCallFields = FilledCallFields(callerArguments: body.callerArgumentByParameter, callerMemoArguments: body.callerMemoArgumentByMemo, labelsHiddenByReenteringCalls: labelsHiddenByReenteringCalls)
		let dispatcherRecords = dispatcherObserver == nil ? [] : body.callDispatchers.map { dispatcher in
			DispatcherRecord(dispatcher: dispatcher, parameters: body.parametersByKey[dispatcher.key, default: []], isSendable: sendableFillKeys.contains(dispatcher.key))
		}
		func observe(_ text: String, ofDispatcherAt index: Int, asRootFunction: Bool) {
			guard let dispatcherObserver else { return }
			dispatcherObserver(DispatcherRecordObservation(
				text: text,
				spelledFromRecord: filledCallFields.declaration(
					of: dispatcherRecords[index],
					among: dispatcherRecords,
					asRootFunction: asRootFunction,
					indent: leadingMemberWhitespace,
					inlinedFills: body.inlinedFills,
					fillParametersByKey: body.fillParametersByKey,
					typesDeclaredEscaping: typesDeclaredEscaping,
					fillsTakingPayloadFields: body.fillsTakingPayloadFields,
				),
			))
		}
		for (index, dispatcher) in body.callDispatchers.enumerated() {
			let isSendable = sendableFillKeys.contains(dispatcher.key)
			guard rootFunctionKeys.contains(dispatcher.key) else {
				let text = dispatcher.declaration(
					isSendable: isSendable,
					indent: leadingMemberWhitespace,
					inlinedFills: body.inlinedFills,
					parametersByKey: body.parametersByKey,
					callerArgumentByParameter: callerArgumentByParameter,
					callerMemoArgumentByMemo: callerMemoArgumentByMemo,
					typesDeclaredEscaping: typesDeclaredEscaping,
					fillsTakingPayloadFields: body.fillsTakingPayloadFields,
					labelsHiddenByReenteringCalls: labelsHiddenByReenteringCalls,
				)
				observe(text, ofDispatcherAt: index, asRootFunction: false)
				generatedProperties.append(.text(text))
				continue
			}
			let rootFunctionText = dispatcher.declaration(
				isSendable: false,
				indent: leadingMemberWhitespace,
				inlinedFills: body.inlinedFills,
				parametersByKey: body.parametersByKey,
				typesDeclaredEscaping: typesDeclaredEscaping,
				fillsTakingPayloadFields: body.fillsTakingPayloadFields,
				labelsHiddenByReenteringCalls: labelsHiddenByReenteringCalls,
			)
			observe(rootFunctionText, ofDispatcherAt: index, asRootFunction: true)
			let targetKeys = dispatcher.cases.compactMap(\.target?.key)
			let inlinedFillKeys = Set(targetKeys.filter { body.inlinedFills[$0] != nil })
			let record = RootFunctionRecord(
				key: RootFunctionKey(
					calledSeam: dispatcher.seamType,
					level: dispatcher.key,
					isSendable: isSendable,
					inlinedFillKeys: inlinedFillKeys,
					fillsTakingPayloadFields: body.fillsTakingPayloadFields.intersection(targetKeys),
					typesDeclaredEscaping: typesDeclaredEscaping,
					labelsHiddenByReenteringCalls: labelsHiddenByReenteringCalls,
					indentation: leadingMemberWhitespace,
				),
				name: dispatcher.functionName,
				// The declaration after its indentation and the attributes it is spelled with (`RootFunctionRecord.spelled`).
				textWithoutAttributes: String(rootFunctionText.dropFirst(leadingMemberWhitespace.count + Self.localFunctionPrefix(isSendable: false).count)),
				isSendable: isSendable,
				calls: dispatcher.cases.compactMap { dispatcherCase in
					dispatcherCase.target.flatMap { body.inlinedFills[$0.key] == nil ? $0.name : nil }
				},
			)
			generatedProperties.append(.rootFunction(record))
		}
		if let publicMockLevelFunctions {
			generatedProperties += publicMockLevelFunctions.records(
				sendableKeys: sendableFillKeys,
				inlinedFills: body.inlinedFills,
				fillsTakingPayloadFields: body.fillsTakingPayloadFields,
				fillMemberParameterFieldsByKey: body.fillParametersByKey,
				typesDeclaredEscaping: typesDeclaredEscaping,
			).declarations(indent: leadingMemberWhitespace, inlinedFillBodies: body.inlinedFills.mapValues(\.body)).map(GeneratedCode.text)
		}
		return generatedProperties
	}

	/// What this scope's call of another module's public mock passes each builder, by label, where the call's fills are
	/// generated with `propertiesGeneratedLater`: the call of the builder's root level function
	/// (`PublicMockLevelFunctions.rootCallsByLabel(passingNilFor:)`), or the struct the caller passes up where the call fills
	/// no place of the builder.
	nonisolated func publicMockBuilderStructValuesByLabel(propertiesGeneratedLater: Set<Property>) -> [String: String] {
		let rootCallsByLabel = publicMockLevelFunctions?.rootCallsByLabel(passingNilFor: callerReadLabelsBuiltAfterCall(propertiesGeneratedLater: propertiesGeneratedLater)) ?? [:]
		var valuesByLabel = [String: String]()
		for builderCallArgument in builderCallArguments {
			guard let builderStruct = builderCallArgument.builderStruct else { continue }
			valuesByLabel[builderCallArgument.label] = rootCallsByLabel[builderCallArgument.label] ?? builderStruct.upValue
		}
		return valuesByLabel
	}

	/// The labels this scope's call's fills read of the caller's scope that no fill finds available, where the fills are
	/// generated with `propertiesGeneratedLater`: the caller builds the value after the call, so each fill reads `nil`, and
	/// the root level function is handed `nil`, as a seam's root dispatcher is (`callerArgumentByParameter`), rather than a
	/// value not yet declared.
	nonisolated private func callerReadLabelsBuiltAfterCall(propertiesGeneratedLater: Set<Property>) -> Set<String> {
		var unavailableLabels = Set<String>()
		var availableLabels = Set<String>()
		for child in orderedChildrenComputedAfresh(propertiesGeneratedLater: propertiesGeneratedLater) where child.generator.fillKey != nil && child.generator.fillEmitsCode {
			let callerReads = child.generator.fillCallerReads
			for label in callerReads.argumentByLabel.keys {
				let forms = callerReads.dependencies.map(\.property).filter { $0.label == label }
				if forms.allSatisfy(child.unavailableProperties.contains) {
					unavailableLabels.insert(label)
				} else {
					availableLabels.insert(label)
				}
			}
		}
		return unavailableLabels.subtracting(availableLabels)
	}

	/// The body of `fill`, whose function is `code` indented by `leadingMemberWhitespace`, as the dispatcher case that calls
	/// it holds it: the function's body under the names the case binds. `nil` for a fill whose scope parameter is named
	/// apart, because its place carries a field or its tree reads a value labeled `scope`, which the dispatcher's own
	/// parameter would hide: it keeps its function.
	private static func inlinedFill(of fill: ScopeGenerator, code: String, leadingMemberWhitespace: String) -> FillDispatcher.InlinedFill? {
		// A fill is its function's declaration, its body, and the line closing it.
		let lines = GeneratedCodeText.lines(of: code)
		let valuesType = fill.fillHole?.valuesType(qualifiedBy: nil)
		let carriesPayload = valuesType != nil
		// A seam's carrier hands the fill the payload's fields as arguments, the first named `scope_<label>`
		// (`SeamHoles.argumentName(of:inPayloadNamed:)`), where a builder struct hands it the payload named `scope`.
		let argumentFields: [SeamSignature.Hole.Field]? = if case let .nested(_, enumType, _)? = valuesType, ReservedName.seamCarrier(ofEnum: enumType) != nil {
			fill.fillHole.map { $0.enumPlace?.values ?? $0.fields } ?? []
		} else {
			nil
		}
		let scopePrefix = argumentFields.map { fields in (fill.fillCarrierUse?.parameterNames(of: fields, inPayloadNamed: "scope") ?? fields.map { SeamHoles.argumentName(of: $0, inPayloadNamed: "scope") }).first.map { "(_ \($0): " } ?? "(" } ?? "(_ scope: "
		guard lines.count > 2,
		      !carriesPayload || lines[0].contains(scopePrefix),
		      lines[lines.count - 1] == leadingMemberWhitespace + "}"
		else { return nil }
		let body = lines[1..<(lines.count - 1)].map { Self.standardIndent + $0 }
		// The fill binds the fields its tree reads first, each from the scope; nothing after them reads the scope.
		// safedi-source-rule: allow stringScan — reads the first line of one inlined fill, once per fill.
		let readsScope = carriesPayload && lines[1].hasPrefix(leadingMemberWhitespace + Self.standardIndent + "let ") && (lines[1].contains(" = scope.") || (argumentFields != nil && lines[1].contains(" = scope_")))
		let builtProperty = fill.propertiesToGenerate.first?.property
		let forwardedValueName = fill.fillHole?.forwardedType == nil ? nil : builtProperty.map(Self.forwardedValueParameterName(forBuilding:))
		let readsForwardedValue = forwardedValueName.map { name in
			body.contains { line in GeneratedCodeText.containsIdentifier(name, in: line) }
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
	/// other site of the gap is `mockRootParameters(instantiable:mockDefaults:treeNames:)`.
	///
	/// Also the calls of other modules' public mocks inside those fills, each with whether it is made inside a `@Sendable`
	/// function, in the order they are generated, whose filled builders `mock()` takes optional builders for
	/// (`FilledCall`).
	/// - Parameter insideSendableFunction: Whether the call is made inside a `@Sendable` function.
	nonisolated func fillPlaces(insideSendableFunction: Bool) -> (places: [FillPlace], declaredLabels: Set<String>, calls: [FilledCall]) {
		var places = [FillPlace]()
		var declaredLabels = Set<String>()
		var calls = [FilledCall]()
		// A stack of its own, since a tree can be as deep as the module has types. Each scope's children are pushed in
		// reverse, so they are visited in the order they are generated.
		var generatorsToVisit = [(generator: ScopeGenerator, isInsideSendableFunction: Bool, enclosingCalls: [ScopeGenerator])]()
		func pushFills(of call: ScopeGenerator, insideSendableFunction: Bool, enclosingCalls: [ScopeGenerator]) {
			for fill in call.propertiesToGenerate.reversed() where fill.fillHole != nil && fill.fillEmitsCode {
				let fillIsInsideSendableFunction = insideSendableFunction || call.buildsInSendableFunction(ofFill: fill)
				for child in fill.propertiesToGenerate.reversed() {
					generatorsToVisit.append((child, fillIsInsideSendableFunction, enclosingCalls))
				}
			}
		}
		pushFills(of: self, insideSendableFunction: insideSendableFunction, enclosingCalls: [self])
		while let (generator, enclosingIsInsideSendableFunction, generatorEnclosingCalls) = generatorsToVisit.popLast() {
			// A scope that closes a cycle builds nothing; an alias builds nothing either.
			guard case let .property(instantiable, property, _, _, false, _) = generator.scopeData else { continue }
			declaredLabels.insert(property.label)
			let isInsideSendableFunction = enclosingIsInsideSendableFunction || generator.buildsInSendableFunction
			if generator.publicMockCall != nil {
				calls.append(FilledCall(generator: generator, isInsideSendableFunction: isInsideSendableFunction, enclosingCalls: generatorEnclosingCalls))
				pushFills(of: generator, insideSendableFunction: isInsideSendableFunction, enclosingCalls: [generator] + generatorEnclosingCalls)
			} else {
				let builtLabels = Set(generator.propertiesToGenerate.compactMap(\.property?.label))
				for dependency in instantiable.dependencies {
					declaredLabels.insert(dependency.property.label)
					if case .instantiated = dependency.source, !builtLabels.contains(dependency.property.label), DependencyTreeGenerator.canBeHole(dependency) {
						places.append(FillPlace(generator: ObjectIdentifier(generator), dependency: dependency, isInsideSendableFunction: isInsideSendableFunction, order: places.count))
					}
				}
				for child in generator.propertiesToGenerate.reversed() {
					generatorsToVisit.append((child, isInsideSendableFunction, generatorEnclosingCalls))
				}
			}
		}
		return (places, declaredLabels, calls)
	}

	/// `code` with each line indented once more.
	private static func indented(_ code: String) -> String {
		GeneratedCodeText.indentingLines(of: code, by: standardIndent)
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
	/// - Parameter inlinePlaceBuilder: Where the scope is a place of a public mock built inline inside a fill, the builder
	///   `mock()` takes for its hole type and family, whose wrapper is declared where the builder is passed or required
	///   (`ScopeGenerator.holeBuildersByInlinePlaceInFills`).
	nonisolated private func instantiatorDeclaration(handing functionName: String, forwardedArguments: String, inlinePlaceBuilder: FillPlaceBindings.HoleBuilder? = nil) -> String {
		guard case let .property(instantiable, property, _, erasedToConcreteExistential, _, _) = scopeData else { return "" }
		return Self.instantiatorDeclaration(
			of: property,
			isExtension: instantiable.declarationType.isExtension,
			isErased: erasedToConcreteExistential,
			handing: functionName,
			forwardedArguments: forwardedArguments,
			inlinePlaceBuilder: inlinePlaceBuilder,
		)
	}

	/// The declaration of the instantiator `property`, which hands its wrapper the function named `functionName`, called
	/// with `forwardedArguments`, of a type declared through an extension where `isExtension` is set, erased where
	/// `isErased` is set, and read through `inlinePlaceBuilder` where it is set
	/// (`instantiatorDeclaration(handing:forwardedArguments:inlinePlaceBuilder:)`).
	static func instantiatorDeclaration(of property: Property, isExtension: Bool, isErased: Bool, handing functionName: String, forwardedArguments: String, onOneLine: Bool = false, inlinePlaceBuilder: FillPlaceBindings.HoleBuilder? = nil) -> String {
		// A type constructed by annotation spells its generic arguments only in the declaration.
		let unwrappedTypeDescription = property
			.typeDescription
			.unwrapped
			.spelledForConstruction
		let propertyDeclaration = BindingDeclaration(
			property: property,
			rule: .instantiator(isExtension: isExtension, constructionSpellsPropertyType: property.typeDescription.asSource == unwrappedTypeDescription),
		)
		let expression = instantiatorExpression(of: property, spelledForConstruction: unwrappedTypeDescription, isErased: isErased, handing: functionName, forwardedArguments: forwardedArguments, onOneLine: onOneLine)
		guard let inlinePlaceBuilder else { return "\(propertyDeclaration.spelled) = \(expression)" }
		return "\(propertyDeclaration.spelled) = \(inlinePlaceBuilder.inlinePlaceValue(construction: expression, overrideExpression: nil, wrappingBuilderIn: unwrappedTypeDescription))"
	}

	/// The wrapper `instantiatorDeclaration(of:isExtension:isErased:handing:forwardedArguments:onOneLine:inlinePlaceBuilder:)`
	/// declares: around the function itself where it is handed nothing and erases nothing, and otherwise around a closure
	/// that calls it, on one line where `onOneLine` holds.
	///
	/// `unwrappedTypeDescription` is the property's unwrapped type as a construction spells it (`spelledForConstruction`),
	/// which a caller that spells it already hands in rather than spelling it again.
	private static func instantiatorExpression(of property: Property, spelledForConstruction unwrappedTypeDescription: String? = nil, isErased erasedToConcreteExistential: Bool, handing functionName: String, forwardedArguments: String, onOneLine: Bool) -> String {
		let unwrappedTypeDescription = unwrappedTypeDescription ?? property
			.typeDescription
			.unwrapped
			.spelledForConstruction
		guard !forwardedArguments.isEmpty || erasedToConcreteExistential else { return "\(unwrappedTypeDescription)(\(functionName))" }
		let call: Expression = .call(function: functionName, arguments: forwardedArguments)
		let closureBody = erasedToConcreteExistential ? Expression.erasure(call, as: property.typeDescription.unwrapped.asInstantiatedType).spelled : call.spelled
		return wrapperClosure(of: unwrappedTypeDescription, calling: closureBody, onOneLine: onOneLine)
	}

	/// `wrapperType` built around a closure whose one statement is `body`: on one line where `onOneLine` holds, else with
	/// `body` on a line of its own.
	static func wrapperClosure(of wrapperType: String, calling body: String, onOneLine: Bool) -> String {
		if onOneLine {
			"\(wrapperType) { \(body) }"
		} else {
			"""
			\(wrapperType) {
			\(standardIndent)\(body)
			}
			"""
		}
	}

	/// The declaration with which a member of a loop of builders rebinds this scope's instantiator, a member of the same
	/// loop, whose builder function its scope's body names `functionName` (see `ReceivedBuilderLoops`): the declaration the
	/// scope's body makes of it, which wraps the function again.
	nonisolated private func loopRebinding(functionName: String, closesOnFunction: Bool) -> LoopRebinding {
		guard case let .property(instantiable, property, forwardedProperties, erasedToConcreteExistential, _, _) = scopeData else { return LoopRebinding(declaration: "", closer: nil) }
		let sortedForwardedProperties = forwardedProperties.sorted()
		return LoopRebinding(
			declaration: instantiatorDeclaration(
				handing: functionName,
				forwardedArguments: Self.forwardedArguments(of: sortedForwardedProperties, spreading: "$0").joined(separator: ", "),
			),
			closer: closesOnFunction ? LoopRebinding.Closer(
				property: property,
				isErased: erasedToConcreteExistential,
				isExtension: instantiable.declarationType.isExtension,
				functionName: functionName,
				forwardedProperties: sortedForwardedProperties,
			) : nil,
		)
	}

	/// How a member of a loop of builders is wrapped again inside the functions of the members whose trees receive it: its
	/// declaration, and, where the declaration hands the member's own builder function, the cycle-closing place the type key
	/// reads of it. A rebinding is a closer on the function a statement of the loop's body declares, rather than one an
	/// enclosing scope declares (`TypeKeyLayout.read(_:)` resolves it as Swift does).
	struct LoopRebinding: Hashable {
		/// The rebinding, unindented.
		let declaration: String
		/// What the type key reads of the rebinding, or `nil` where it hands a `__safeDI_<label>_received` function or wraps a
		/// rename, which the type key does not lay out.
		let closer: Closer?

		struct Closer: Hashable {
			let property: Property
			let isErased: Bool
			let isExtension: Bool
			let functionName: String
			let forwardedProperties: [Property]
		}

		/// The place the type key reads, where it lays the rebinding out.
		var record: PlaceRecord? {
			closer.map { closer in
				.closer(ClosingPlaceRecord(
					property: closer.property,
					isErased: closer.isErased,
					isExtension: closer.isExtension,
					closedOnFunctionName: closer.functionName,
					forwardedProperties: closer.forwardedProperties,
					cycleArguments: [],
					rebindsLoopMember: true,
				))
			}
		}
	}

	/// The declaration with which a member of a loop of builders rebinds this scope, a rename its scope declares of a member
	/// of the same loop, whose rebinding is `fulfillingDeclaration`: the rename bound to a wrapper made again of the member's
	/// function. `nil` for any other scope.
	nonisolated private func loopRebindingDeclaration(ofRenameOf fulfillingDeclaration: (property: Property, generator: ScopeGenerator, functionName: String)) -> String? {
		guard case let .alias(property, _, _, _, _) = scopeData,
		      case let .property(_, fulfillingProperty, forwardedProperties, fulfillingIsErased, _, _) = fulfillingDeclaration.generator.scopeData
		else { return nil }
		return Self.aliasDeclaration(
			of: property,
			fulfilledBy: Self.instantiatorExpression(
				of: fulfillingProperty,
				isErased: fulfillingIsErased,
				handing: fulfillingDeclaration.functionName,
				forwardedArguments: Self.forwardedArguments(of: forwardedProperties.sorted(), spreading: "$0").joined(separator: ", "),
				onOneLine: false,
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
		var loopMemberDeclarations = [Property: LoopRebinding]()
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
				name: holeWrapperFunctionName,
				declaresFunction: declaresBuilderFunction,
				cycleClosedOnDeclarations: cycleClosedOnDeclarations,
				isReferencedByCycleClosingScope: isReferencedByCycleClosingScope,
				referencedFillNames: Set(referencedFillNamesByKey.values),
			)
		}
	}

	/// The name of the function a site of a hole held in a wrapper declares, which its site names apart from the builder
	/// the function calls (`HoleSiteRecord`), or `nil` for any other scope, whose function is `functionName(toBuild:)`.
	nonisolated private var holeWrapperFunctionName: String? {
		guard case let .hole(_, _, site) = scopeData else { return nil }
		return site?.wrapperFunctionName
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
	/// delegate to `generateMockRootCode`; non-root mock code is produced by
	/// the mock's lowering (`MockLowering`) instead.
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
					// Only a seam’s tree declares its local functions `@inline(never)` (`LocalFunctionInlining`).
					return try await LocalFunctionInlining.$isNeverInlined.withValue(true) {
						try await .text(generateSeamRootCode(
							instantiable: instantiable,
							seamRoot: seamRoot,
							unavailableProperties: unavailableProperties,
							propertiesGeneratedLater: propertiesGeneratedLater,
							builderFunctionNames: builderFunctionNames,
							fillPlaceBindings: fillPlaceBindings,
						))
					}
				}
				guard let rootInitializer = try Self.rootInitializer(of: instantiable) else { return .empty }
				// A root’s tree keeps its local functions inlinable, where a seam’s does not (`LocalFunctionInlining`).
				// A root of the dependency tree plans its children at once (`ConcurrentChildCode`).
				let childCode = try await ConcurrentChildCode.$plansChildrenAtOnce.withValue(true) {
					try await generateProperties(
						propertiesGeneratedLater: propertiesGeneratedLater,
						enclosingFunctionNames: builderFunctionNames.enclosingFunctionNames,
						leadingMemberWhitespace: "        ",
						fillPlaceBindings: fillPlaceBindings,
					)
				}
				// A test that observes node records compares this body with theirs.
				NodeRecordsObservation.rootBodyObserver?(childCode)
				return Self.rootCode(of: rootInitializer, writing: consume childCode)
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
			let argumentList = try constructionArgumentList(of: instantiable, unavailableProperties: unavailableProperties, propertiesGeneratedLater: propertiesGeneratedLater, holeBuilders: fillPlaceBindings.holeBuildersByCall[ObjectIdentifier(self)] ?? [:])
			if isPropertyCycle, let closingCode = cycleClosingCode(
				of: property,
				erasedToConcreteExistential: erasedToConcreteExistential,
				unavailableProperties: unavailableProperties,
				builderFunctionNames: builderFunctionNames,
			) {
				return closingPlace(
					closingCode: closingCode,
					of: property,
					instantiable: instantiable,
					erasedToConcreteExistential: erasedToConcreteExistential,
					unavailableProperties: unavailableProperties,
					builderFunctionNames: builderFunctionNames,
					fillPlaceBindings: fillPlaceBindings,
				)
			}
			let childCode = try await generateProperties(
				codeGeneration: codeGeneration,
				propertiesGeneratedLater: bodyPropertiesGeneratedLater(propertiesGeneratedLater),
				enclosingFunctionNames: builderFunctionNames.enclosingFunctionNames,
				leadingMemberWhitespace: Self.standardIndent,
				fillPlaceBindings: fillPlaceBindings,
			)
			return try placeCode(
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
			// The seam side of hosting seam code as text, a hole's site here and a seam's root in
			// `generateSeamRootCode`, lives until the 2.3.1 seam rework (R2a) plans seam bodies, fills and level
			// functions on the builder graph and deletes today's seam emission with it. The caller side, a fill below,
			// stays until fills are planned. Node records write a hole's place with the same function
			// (`NodeRecords.holePlace(of:in:seamHoles:)`).
			return HoleSitePlaces.place(
				of: property,
				at: site,
				routeMembers: siteRouteMembers,
				functionName: builderFunctionNames.functionName,
				valuesBindings: valuesBindings,
				carrierUse: siteCarrierUse,
				readingInstancesOf: callSiteLazilyInstantiatedInstanceProperties,
				loopBindsPayloads: builderFunctionNames.loopValuesBindingLines != nil,
			)
		case let .fill(hole, functionName):
			// A fill is hosted as its text until fills are planned (`.claude/rules/emission-decisions.md`).
			let fillCode = try await generateFillCode(
				of: hole,
				functionName: functionName,
				isSendable: builderFunctionNames.fillIsSendable,
				takesPayloadFields: builderFunctionNames.fillTakesPayloadFields,
				codeGeneration: codeGeneration,
				propertiesGeneratedLater: propertiesGeneratedLater,
				enclosingFunctionNames: builderFunctionNames.enclosingFunctionNames,
				fillPlaceBindings: fillPlaceBindings,
			)
			return Self.textPlace(fillCode)
		case let .alias(property, fulfillingProperty, erasedToConcreteExistential, onlyIfAvailable, declarationReference):
			return aliasPlace(
				of: property,
				fulfilledBy: fulfillingProperty,
				erasedToConcreteExistential: erasedToConcreteExistential,
				onlyIfAvailable: onlyIfAvailable,
				declarationReference: declarationReference,
				unavailableProperties: unavailableProperties,
			)
		}
	}

	// The four functions below build a place's record, a struct of many fields, in a frame of their own: inlined into
	// `generatePropertyCode`, whose async frame every task planning a scope holds, the record's temporaries grew that frame
	// by about 5.6 KB, and the peak memory of a module of 1,200 seams by about 15 MB.

	/// The record of the place of `property`, instantiated only if available, where nothing fulfills it. Its `nil` reads
	/// nothing, which the record lists, so the type key lays it out as written, as it does an alias bound to `nil`: a place
	/// that records nothing would keep the bodies of the root's tree one per path.
	/// A place that records nothing, written as `text`.
	@inline(never)
	private static func textPlace(_ text: String) -> GeneratedCode {
		.place(PlacePlan(code: .text(text)))
	}

	/// The place of a scope that closes a cycle, written as `closingCode`.
	@inline(never)
	private func closingPlace(
		closingCode: String,
		of property: Property,
		instantiable: Instantiable,
		erasedToConcreteExistential: Bool,
		unavailableProperties: Set<Property>,
		builderFunctionNames: BuilderFunctionNames,
		fillPlaceBindings: FillPlaceBindings,
	) -> GeneratedCode {
		let closedOnFunctionName = closedOnFunctionName(builtFor: property, enclosingFunctionNames: builderFunctionNames.enclosingFunctionNames)
		return .place(PlacePlan(code: .text(closingCode),
		                        record: closingRecord(
		                        	of: property,
		                        	instantiable: instantiable,
		                        	forwardedProperties: [],
		                        	erasedToConcreteExistential: erasedToConcreteExistential,
		                        	closedOnFunctionName: closedOnFunctionName,
		                        	unavailableProperties: unavailableProperties,
		                        	builderFunctionNames: builderFunctionNames,
		                        	fillPlaceBindings: fillPlaceBindings,
		                        )))
	}

	/// The place of a scope that builds its property around `childCode` (`propertyCode`).
	@inline(never)
	private func placeCode(
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
	) throws(Initializer.GenerationError) -> GeneratedCode {
		let valuesBindingPlaces = valuesBindingPlaces(builderFunctionNames: builderFunctionNames)
		let plan = try propertyCode(
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
			separatesValuesBindings: valuesBindingPlaces != nil,
		)
		guard let valuesBindingPlaces else { return .place(plan) }
		return .sequence(valuesBindingPlaces + [.place(plan)])
	}

	/// The payloads `valuesBindingLines` binds, each a place of its own written as its text, which lists what its line
	/// reads, so the type key lays them out as the scope's parent's statements; `nil` where there are none, or where a
	/// loop's box holds them.
	nonisolated private func valuesBindingPlaces(builderFunctionNames: BuilderFunctionNames) -> [GeneratedCode]? {
		guard builderFunctionNames.loopValuesBindingLines == nil else { return nil }
		return HoleSitePlaces.valuesBindingPlaces(of: valuesBindings, readingInstancesOf: callSiteLazilyInstantiatedInstanceProperties)
	}

	/// The place of an alias's declaration.
	@inline(never)
	private func aliasPlace(
		of property: Property,
		fulfilledBy fulfillingProperty: Property,
		erasedToConcreteExistential: Bool,
		onlyIfAvailable: Bool,
		declarationReference: AliasDeclarationReferences.Reference?,
		unavailableProperties: Set<Property>,
	) -> GeneratedCode {
		let aliasCode = aliasCode(
			of: property,
			fulfilledBy: fulfillingProperty,
			erasedToConcreteExistential: erasedToConcreteExistential,
			onlyIfAvailable: onlyIfAvailable,
			declarationReference: declarationReference,
			unavailableProperties: unavailableProperties,
		)
		let record: PlaceRecord? = if fulfillingExpression == nil {
			// An alias bound to `nil` reads nothing, which its record lists, so the type key lays it out as written.
			if Self.aliasIsBoundToNil(onlyIfAvailable: onlyIfAvailable, fulfillingProperty: fulfillingProperty, unavailableProperties: unavailableProperties) {
				.alias(AliasPlaceRecord(property: property, fulfillingProperty: nil, text: aliasCode, reads: []))
			} else {
				.alias(AliasPlaceRecord(property: property, fulfillingProperty: fulfillingProperty, text: aliasCode, readsOnlyIfAvailable: fulfillingBindingIsOptional))
			}
		} else {
			nil
		}
		return .place(PlacePlan(code: .text(aliasCode), record: record))
	}

	/// The initializer generated for `instantiable`, a root of the dependency tree, or `nil` for a root without
	/// dependencies, for which nothing is generated (`RootInitializer.init(of:argumentList:)`).
	@inline(never)
	static func rootInitializer(of instantiable: Instantiable) throws -> RootInitializer? {
		try RootInitializer(of: instantiable, argumentList: instantiable.generateArgumentList())
	}

	/// The extension `rootInitializer` declares, writing `childCode`, the code of the root's children.
	@inline(never)
	private static func rootCode(of rootInitializer: RootInitializer, writing childCode: consuming [GeneratedCode]) -> GeneratedCode {
		// The type key lays the body out again from the path key's plan, or keeps the path key's body where it cannot.
		// A root the type key leaves on the path layout still declares its root functions once, at its top.
		guard let statements = TypeKeyBody.statements(ofRootBody: childCode) else {
			let hoisted = RootFunctionHoisting.hoisted(childCode, indentation: TypeKeyBody.rootStatementIndentation)
			return rootInitializer.spelled(writing: BuilderFunctionGraph(body: hoisted.map(Statement.verbatim)))
		}
		return rootInitializer.spelled(writing: BuilderFunctionGraph(body: statements.map(Statement.verbatim)))
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
	/// - Parameter propertiesGeneratedLater: The properties generated after this scope, from which its body's children,
	///   the fills of a call of another module's public mock among them, are generated (`bodyPropertiesGeneratedLater(_:)`).
	/// - Parameter holeBuilders: For a call of another module's public mock, the builders `mock()` takes for the places of
	///   each called builder it fills, by the called builder's label (`FillPlaceBindings.holeBuildersByCall`).
	@inline(never)
	private func constructionArgumentList(of instantiable: Instantiable, unavailableProperties: Set<Property>, propertiesGeneratedLater: Set<Property>, holeBuilders: [String: FillPlaceBindings.HoleBuilder]) throws -> String {
		// A type built with its hand-written mock, as one built with its initializer, is constructed inside its builder
		// function, whose own parameters hide the declarations of their labels where it is called.
		if publicMockCall != nil, let mockInitializer = instantiable.mockInitializer {
			// A call of another module's public mock in a fill a mock declares, which passes each parameter of the tier
			// in signature order, a builder it fills among them, and no `safeDIOverrides`: no override reaches a fill. A
			// by-value parameter whose label the tree holds as a lazily instantiated property is passed its instance, as
			// a call outside a fill is (`dependencyArgument`).
			let builderStructValuesByLabel = publicMockBuilderStructValuesByLabel(propertiesGeneratedLater: bodyPropertiesGeneratedLater(propertiesGeneratedLater))
			return mockInitializer.arguments.map { argument in
				let dependency = instantiable.dependencies.first { $0.property.label == argument.innerLabel }
				let source: ArgumentSource = if let builderValue = builderStructValuesByLabel[argument.innerLabel] {
					.builderArgument(holeBuilders[argument.innerLabel]?.structValue(fillsStruct: builderValue) ?? builderValue)
				} else if let holeValue = holeArgumentValuesByLabel[argument.innerLabel] {
					// A call that re-enters an enclosing call's level function hands it on as the enclosing call does.
					.spelledArgument(holeBuilders[argument.innerLabel]?.structValue(fillsStruct: holeValue) ?? holeValue)
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
			return mockInitializer.createHandWrittenMockArgumentList(
				given: instantiable.dependencies,
				unavailableProperties: bodyUnavailableProperties(unavailableProperties),
				lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties,
			)
		} else {
			// A public mock takes a value its tree receives lazily as the wrapper, so a call of one passes the caller's own
			// (`ScopeGenerator.publicMockWrapperParameters`). A deliberate gap, the other site of which is that function: where
			// the called mock still takes the value by value, a call passes a `LazilyInstantiated` property's instance
			// (`<label>.instance`), which is created at the call, even when nothing in the called mock's tree reads it.
			// A second deliberate gap, the other site of which is the graph fuzzer's M8.32 exemption
			// (`statedPublicMockValueDivergences`), stated in `public-mock-builders.md`: where the called mock takes a
			// plain value (`x: T`, or `x: T? = nil`, which 2.3.0 shipped as API), the call reads `.instance` too. Where the
			// called tree reads the value only behind an instantiator, the instance is created at the call rather than at
			// that first read; elsewhere the called type's own construction reads it, and only the order of creation within
			// that construction moves.
			return try instantiable.generateArgumentList(
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
	/// `lazilyInstantiatedInstantiation(of:callingFunctionNamed:cycleArguments:erasedToConcreteExistential:)`, or, where the
	/// scope is a place of a public mock built inline inside a fill, the wrapper of the builder `mock()` takes for its hole
	/// type and family where it is passed or required (`ScopeGenerator.holeBuildersByInlinePlaceInFills`).
	@inline(never)
	private static func lazilyInstantiatedValue(
		of property: Property,
		callingFunctionNamed functionName: String,
		cycleArguments: String,
		erasedToConcreteExistential: Bool,
		inlinePlaceBuilder: FillPlaceBindings.HoleBuilder?,
	) -> String {
		let instantiation = lazilyInstantiatedInstantiation(of: property, callingFunctionNamed: functionName, cycleArguments: cycleArguments, erasedToConcreteExistential: erasedToConcreteExistential)
		guard let inlinePlaceBuilder else { return instantiation }
		return inlinePlaceBuilder.inlinePlaceValue(construction: instantiation, overrideExpression: nil, wrappingBuilderIn: property.typeDescription.unwrapped.asSource)
	}

	static func lazilyInstantiatedInstantiation(
		of property: Property,
		callingFunctionNamed functionName: String,
		cycleArguments: String,
		erasedToConcreteExistential: Bool,
		onOneLine: Bool = false,
	) -> String {
		let unwrappedTypeDescription = property
			.typeDescription
			.unwrapped
			.asSource
		guard !cycleArguments.isEmpty || erasedToConcreteExistential else { return "\(unwrappedTypeDescription)(\(functionName))" }
		let call: Expression = .call(function: functionName, arguments: cycleArguments)
		let closureBody = erasedToConcreteExistential ? Expression.erasure(call, as: property.typeDescription.asInstantiatedType).spelled : call.spelled
		return wrapperClosure(of: unwrappedTypeDescription, calling: closureBody, onOneLine: onOneLine)
	}

	/// The code of this scope, which builds `property` from `instantiable`, written around `childCode`, its children's
	/// code: the builder function, where the scope declares one, and the declaration of the property. A scope that closes
	/// a lazily instantiated or constant cycle is written by `cycleClosingCode(of:erasedToConcreteExistential:unavailableProperties:builderFunctionNames:)`.
	/// - Parameter argumentList: What the construction passes the function it calls
	///   (`constructionArgumentList(of:unavailableProperties:propertiesGeneratedLater:holeBuilders:)`).
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
		separatesValuesBindings: Bool,
	) throws(Initializer.GenerationError) -> PlacePlan {
		let concreteTypeName = instantiable.concreteInstantiable.asSource
		let constructionTarget: ConstructionTarget = if isUnavailableDependency {
			.unavailable
		} else if let publicMockCall {
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
		// Where they are places of their own (`valuesBindingPlaces`), the scope's parent holds them before this place.
		let valuesBindingLines = separatesValuesBindings ? "" : builderFunctionNames.loopValuesBindingLines ?? valuesBindingLines
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
		// A place built by its own construction calls the members its `@Sendable` builder function binds as places of their own
		// (`memberCallPlaces`), the first statements of the function's body, so the type key lays the function out; a place
		// written as text keeps them as lines of that text.
		let separatesMemberCalls = seamCall == nil && !isPropertyCycle && !isBuiltByFill && builderFunctionNames.receivedFunctionName == nil
		let memberCallCode = separatesMemberCalls ? memberCallPlaces : memberCallLines.map(GeneratedCode.text)
		// A place of a public mock built inline inside a fill reads the builder `mock()` takes for its hole type and family, as
		// the place does where the fill calls that public mock (`ScopeGenerator.holeBuildersByInlinePlaceInFills`).
		let inlinePlaceBuilder = fillPlaceBindings.holeBuildersByInlinePlace[ObjectIdentifier(self)]
		// What the type key reads of the place, where it plans it: a place built by its own construction, with nothing but
		// its children in its function's body.
		let isBuiltPlacePlannedByTypeKey = seamCall == nil && isPlannedByTypeKey(builderFunctionNames: builderFunctionNames, fillPlaceBindings: fillPlaceBindings, separatesValuesBindings: separatesValuesBindings, separatesMemberCalls: separatesMemberCalls)
		let isPlannedByTypeKey = seamCall == nil && isPlannedByTypeKey(builderFunctionNames: builderFunctionNames, fillPlaceBindings: fillPlaceBindings, separatesValuesBindings: separatesValuesBindings)
		// A member of a loop of builders writes its rebindings, places of their own, between its member calls and its children.
		func builtRecord(functionName: String, hasFunction: Bool, rebindings: [GeneratedCode] = []) throws(Initializer.GenerationError) -> PlaceRecord? {
			guard isBuiltPlacePlannedByTypeKey, let arguments = try constructionReads(of: instantiable, unavailableProperties: unavailableProperties) else { return nil }
			return .built(BuiltPlaceRecord(
				property: property,
				isErased: erasedToConcreteExistential,
				concreteType: instantiable.concreteInstantiable,
				isExtension: instantiable.declarationType.isExtension,
				target: constructionTarget,
				arguments: arguments,
				forwardedProperties: forwardedProperties.sorted(),
				cycleParameters: cycleParameters.map(\.property),
				callCycleArguments: cycleParameterReads(unavailableProperties: unavailableProperties),
				functionName: functionName,
				isSendable: buildsInSendableFunction,
				typesDeclaredEscaping: typesDeclaredEscaping,
				lineEnd: constructionLineEnd,
				hasFunction: hasFunction,
				children: memberCallCode + rebindings + childCode,
				node: PlanNode(),
			))
		}

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
			// A scope that closes a cycle declares no function of its own and calls the one it repeats, though a loop member that
			// closes one declares its `_received` function; every other declares its own.
			func place(declaring _: [String] = [], code: GeneratedCode) -> PlacePlan {
				if isPropertyCycle {
					PlacePlan(code: code)
				} else {
					PlacePlan(code: code)
				}
			}
			let rebindingLines = reboundProperties.compactMap { reboundProperty in
				if reboundProperty == property, declaresCycleParameters {
					// The function's own property is wrapped again with the function's own parameters: where a cycle-closing
					// scope builds the tree again, they are that scope's, which is then the nearest declaration of each.
					GeneratedCode.text(Self.indented(instantiatorDeclaration(
						handing: functionName,
						forwardedArguments: (
							Self.forwardedArguments(of: forwardedProperties, spreading: "$0")
								+ cycleParameters.map { CallArgument(label: $0.property.label, source: .binding(label: $0.property.label)).spelled },
						).joined(separator: ", "),
					)))
				} else {
					builderFunctionNames.loopMemberDeclarations[reboundProperty].map { rebinding in
						GeneratedCode.indented(.place(PlacePlan(code: .text(rebinding.declaration), record: rebinding.record)), by: Self.standardIndent)
					}
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
			generatedProperties += memberCallCode
			generatedProperties += rebindingLines
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
				return place(code: .sequence([.text(valuesBindingLines), functionDeclaration, .text("return { \(forwardedProperties.isEmpty ? "_" : forwardedName) in \(builtValue) }")]))
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
						memberLines.append(Self.indented(memberDeclaration.declaration))
						return CallArgument(label: parameter.property.label, source: .binding(label: parameter.property.label)).spelled
					} else {
						return argument
					}
				}
				let receivedFunctionParameters = forwardedProperties.isEmpty
					? ""
					: forwardedProperties.initializerFunctionParametersSource(amongTypesDeclaredEscaping: typesDeclaredEscaping)
				let callArguments = (forwardedProperties.map { CallArgument(label: $0.label, source: .binding(label: $0.label)).spelled } + cycleArguments).joined(separator: ", ")
				let receivedFunctionDecorator = Self.localFunctionPrefix(isSendable: buildsInSendableFunction || property.propertyType.isSendable)
				let receivedFunctionDeclaration = """
				\(receivedFunctionDecorator)func \(receivedFunctionName)(\(receivedFunctionParameters)) -> \(concreteTypeName) {
				\((memberLines + ["\(Self.standardIndent)\(BuilderBody(statements: memberLines.map(GeneratedCode.text)).returnKeyword)\(functionName)(\(callArguments))"]).joined(separator: "\n"))
				}

				"""
				return place(declaring: [receivedFunctionName], code: .sequence([
					.text(valuesBindingLines),
					functionDeclaration,
					.text(receivedFunctionDeclaration + instantiatorDeclaration(
						handing: receivedFunctionName,
						forwardedArguments: Self.forwardedArguments(of: forwardedProperties, spreading: forwardedValue).joined(separator: ", "),
					)),
				]))
			}
			let code = GeneratedCode.sequence([.text(valuesBindingLines), functionDeclaration, .text(instantiatorDeclaration(handing: functionName, forwardedArguments: forwardedArguments, inlinePlaceBuilder: inlinePlaceBuilder))])
			let record: PlaceRecord? = if isPropertyCycle {
				isPlannedByTypeKey ? closingRecord(
					of: property,
					instantiable: instantiable,
					forwardedProperties: forwardedProperties,
					erasedToConcreteExistential: erasedToConcreteExistential,
					closedOnFunctionName: functionName,
					unavailableProperties: unavailableProperties,
					builderFunctionNames: builderFunctionNames,
					fillPlaceBindings: fillPlaceBindings,
				) : nil
			} else if let seamCall {
				// A seam call's forwarded values are bound inside its text, which lists only the reads outside it.
				try seamCallRecord(of: property, instantiable: instantiable, seamCall: seamCall, erasedToConcreteExistential: erasedToConcreteExistential, forwardedProperties: forwardedProperties, code: code, declaredFunctionName: functionName, unavailableProperties: unavailableProperties, builderFunctionNames: builderFunctionNames, fillPlaceBindings: fillPlaceBindings, inlinePlaceBuilder: inlinePlaceBuilder, separatesValuesBindings: separatesValuesBindings, inPlaceStatements: nil, lineEnd: constructionLineEnd)
			} else {
				try builtRecord(functionName: functionName, hasFunction: true, rebindings: rebindingLines)
			}
			return place(code: code).with(record: record)
		case .lazilyInstantiated,
		     .sendableLazilyInstantiated:
			// The builder function is the one a constant with children declares. A constant calls it
			// immediately; a lazily instantiated property hands it to its wrapper, which calls it the
			// first time the instance is requested. Dependency cycle validation treats the property
			// as a constant, so it is never the deferred hop of a cycle.
			let cycleArguments = cycleParameterArguments(unavailableProperties: unavailableProperties).joined(separator: ", ")
			let functionName = builderFunctionNames.functionName ?? Self.functionName(toBuild: property)
			let generatedProperties = memberCallCode + seamGuardLines + fillPlaceBindingLines + childCode
			// The function a cycle closes on also takes the parameters its cycle-closing scopes pass.
			let function = BuilderNode(
				name: functionName,
				isSendable: buildsInSendableFunction,
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
				"\(BindingDeclaration(property: property, rule: .lazilyInstantiated).spelled) = \(Self.lazilyInstantiatedValue(of: property, callingFunctionNamed: functionName, cycleArguments: cycleArguments, erasedToConcreteExistential: erasedToConcreteExistential, inlinePlaceBuilder: inlinePlaceBuilder))"
			}

			let code = function.spelled(after: valuesBindingLines, followedBy: lastLine)
			let record: PlaceRecord? = if let seamCall {
				try seamCallRecord(of: property, instantiable: instantiable, seamCall: seamCall, erasedToConcreteExistential: erasedToConcreteExistential, code: code, declaredFunctionName: functionName, unavailableProperties: unavailableProperties, builderFunctionNames: builderFunctionNames, fillPlaceBindings: fillPlaceBindings, inlinePlaceBuilder: inlinePlaceBuilder, separatesValuesBindings: separatesValuesBindings, inPlaceStatements: nil, lineEnd: constructionLineEnd)
			} else {
				try builtRecord(functionName: functionName, hasFunction: true)
			}
			return PlacePlan(code: code, record: record)
		case .constant:
			let callArguments = cycleParameterArguments(unavailableProperties: unavailableProperties).joined(separator: ", ")
			let generatedProperties = memberCallCode + seamGuardLines + fillPlaceBindingLines + childCode
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
					parameters: cycleParameters.map(\.property),
					typesDeclaredEscaping: typesDeclaredEscaping,
					returnType: instantiable.concreteInstantiable,
					body: body,
					value: construction,
					lineEnd: constructionLineEnd,
				)).spelled
			}
			let value = if !hasGeneratedContent {
				construction.erased(to: property.typeDescription.unwrapped, where: erasedToConcreteExistential)
			} else {
				Expression.call(function: functionName, arguments: callArguments).erased(to: property.typeDescription.unwrapped, where: erasedToConcreteExistential)
			}
			let binding = Statement.binding(
				propertyDeclaration,
				inlinePlaceBuilder.map { .holeBuilderRead($0, otherwise: value) } ?? value,
				lineEnd: hasGeneratedContent ? "" : constructionLineEnd,
			)

			// The payloads a seam's tree binds before building a scope that leads to a place.
			let code = GeneratedCode.sequence([.text(valuesBindingLines), functionDeclaration, binding.spelled, .text("\n")])
			// A call of another module's seam is written as its text, which the type key lays out with the reads it lists: its
			// builder function holds the guard line, which the type key's constructions do not write.
			let record: PlaceRecord? = if let seamCall {
				try seamCallRecord(of: property, instantiable: instantiable, seamCall: seamCall, erasedToConcreteExistential: erasedToConcreteExistential, code: code, declaredFunctionName: hasGeneratedContent ? functionName : nil, unavailableProperties: unavailableProperties, builderFunctionNames: builderFunctionNames, fillPlaceBindings: fillPlaceBindings, inlinePlaceBuilder: inlinePlaceBuilder, separatesValuesBindings: separatesValuesBindings, inPlaceStatements: valuesBindingLines.isEmpty && hasGeneratedContent ? (before: memberCallCode, after: fillPlaceBindingLines + childCode) : nil, lineEnd: constructionLineEnd)
			} else if isUnavailableDependency {
				.alias(HoleSitePlaces.recordOfPropertyBoundToNil(property))
			} else {
				try builtRecord(functionName: functionName, hasFunction: hasGeneratedContent)
			}
			return PlacePlan(code: code, record: record)
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
		declaresLevelsWithoutScope: Bool,
	) -> [String] {
		guard let ownType = builders.first?.enumKey.seamType else { return [] }
		let holesBySite = Dictionary(holes.map { ($0.site, $0) }, uniquingKeysWith: { first, _ in first })
		let calledRootsTakingValue = declaresLevelsWithoutScope ? LevelsWithoutScope.calledRootsTakingValue(amongEnumsOf: scopeEnums, filledBy: scopeEnums.filter { $0.key.seamType == ownType }) : []
		// Each level's form is computed once per hole type: the builder structs ask for the form of a level once for every case
		// that holds it.
		var levelFormsByHoleType = [SeamSignature.HoleType: LevelBuilderForms]()
		let ownEnums = scopeEnums.filter { $0.key.seamType == ownType }
		let carrierValues = SeamCarrierValues(scopeEnums: ownEnums, ofSeam: nil)
		let valuesStructs = carrierValues.declarations(fieldsByLevel: SeamCarrierValues.fieldsByLevel(of: ownEnums), typesDeclaredEscaping: typesDeclaredEscaping, indent: standardIndent)
		return valuesStructs + scopeEnums.filter { $0.rootTypeName == nil && $0.key.seamType == ownType }.map { scopeEnum in
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
			var levelForms = levelFormsByHoleType[key.holeType] ?? LevelBuilderForms(enumsOfHoleType: scopeEnums.filter { $0.key.holeType == key.holeType })
			let declaration = scopeEnumDeclaration(of: scopeEnum, nestedEnums: nestedEnums, typesDeclaredEscaping: typesDeclaredEscaping, levelForms: &levelForms, declaresLevelsWithoutScope: declaresLevelsWithoutScope, calledRootsTakingValue: calledRootsTakingValue, carrierValues: carrierValues)
			levelFormsByHoleType[key.holeType] = levelForms
			guard let marker = unreadTypeComment?.markerLine(namedBy: namedTypes, indent: standardIndent) else { return declaration }
			return "\(marker)\n\(declaration)"
		}
	}

	/// The declaration of `scopeEnum`, nested in the seam or the public mock, a namespace no generated code builds or switches
	/// over a case of: each case's payload struct, in the order the generated code first reaches the cases, then, for a root
	/// enum nested by type, each of `nestedEnums`, then its builder struct. `public`, so its access is the seam's.
	/// - Parameters:
	///   - levelForms: The forms of the levels of every enum of the hole type of `scopeEnum`, both families', which decide
	///     the type each level's builder struct takes from the builder a person writes.
	///   - declaresLevelsWithoutScope: Whether each builder struct declares `init(__safeDI_noScope:)`, as a public mock's do:
	///     a seam's levels declare none, and the code that needs a seam's level built from one builder builds it with
	///     functions of its own (`LevelsWithoutScope`).
	///   - calledRootsTakingValue: The called mocks' root enums whose struct takes a builder that takes a value from its
	///     no-scope initializer (`LevelsWithoutScope.calledRootsTakingValue(amongEnumsOf:filledBy:)`).
	static func scopeEnumDeclaration(of scopeEnum: SeamSignature.ScopeEnum, nestedEnums: [SeamSignature.ScopeEnum] = [], typesDeclaredEscaping: Set<TypeDescription>, levelForms: inout LevelBuilderForms, declaresLevelsWithoutScope: Bool, calledRootsTakingValue: Set<SeamSignature.ScopeEnum.Key> = [], carrierValues: SeamCarrierValues = SeamCarrierValues(), indent: String = standardIndent) -> String {
		if ReservedName.seamCarrier(ofEnum: scopeEnum.type) != nil {
			// A seam's levels are carriers, declared side by side in the seam's extension: no namespace and no payload struct.
			var carriers = [String]()
			for level in [scopeEnum] + (scopeEnum.rootTypeName == nil ? nestedEnums : []) where !level.cases.isEmpty {
				carriers.append(builderStructDeclaration(of: level, levelForms: &levelForms, declaresLevelsWithoutScope: declaresLevelsWithoutScope, calledRootsTakingValue: calledRootsTakingValue, typesDeclaredEscaping: typesDeclaredEscaping, carrierValues: carrierValues, indent: indent))
			}
			return carriers.joined(separator: "\n\n")
		}
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
				body += (body.isEmpty ? "" : "\n\n") + scopeEnumDeclaration(of: nestedEnum, typesDeclaredEscaping: typesDeclaredEscaping, levelForms: &levelForms, declaresLevelsWithoutScope: declaresLevelsWithoutScope, calledRootsTakingValue: calledRootsTakingValue, indent: caseIndent)
			}
		}
		// A root of the plain family with no case of its own, a namespace for the enums its `@Sendable` root's cases hold,
		// declares no struct: no builder is handed one.
		if !scopeEnum.cases.isEmpty {
			body += (body.isEmpty ? "" : "\n\n") + builderStructDeclaration(of: scopeEnum, levelForms: &levelForms, declaresLevelsWithoutScope: declaresLevelsWithoutScope, calledRootsTakingValue: calledRootsTakingValue, typesDeclaredEscaping: typesDeclaredEscaping, carrierValues: carrierValues, indent: caseIndent)
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
		init(enumsOfHoleType: [SeamSignature.ScopeEnum]) {
			enumsByKey = Dictionary(enumsOfHoleType.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
		}

		/// The form of the builder a person writes for the places at and beneath the level of `key`, in that level's family.
		mutating func form(ofLevel key: SeamSignature.ScopeEnum.Key) -> DependencyTreeGenerator.BuilderForm {
			if let form = formByKey[key] {
				return form
			} else {
				var placeBySpelling = [PlaceSpelling: Property]()
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
				let form = DependencyTreeGenerator.builderForm(ofPlaceProperties: placeBySpelling.sorted { $0.key < $1.key }.map(\.value))
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
			init(of place: Property) {
				let isAnyInstantiator = place.propertyType.isAnyInstantiator
				self.isAnyInstantiator = isAnyInstantiator
				wrapper = isAnyInstantiator ? place.typeDescription.unwrapped.strippingEscaping.asSource : ""
				forwarded = isAnyInstantiator ? place.typeDescription.forwardedTypeOfWrapper?.strippingEscaping.asSource : nil
			}

			let isAnyInstantiator: Bool
			let wrapper: String
			let forwarded: String?

			static func < (lhs: PlaceSpelling, rhs: PlaceSpelling) -> Bool {
				(lhs.isAnyInstantiator ? 1 : 0, lhs.wrapper, lhs.forwarded ?? "") < (rhs.isAnyInstantiator ? 1 : 0, rhs.wrapper, rhs.forwarded ?? "")
			}
		}

		/// One place of each spelling among the places of `scopeEnum`'s own cases, each the property its site's path ends
		/// with, which a caller reads of another module's seam as that seam's module does.
		private mutating func ownPlaces(of scopeEnum: SeamSignature.ScopeEnum) -> [PlaceSpelling: Property] {
			if let places = ownPlacesByKey[scopeEnum.key] {
				return places
			} else {
				var places = [PlaceSpelling: Property]()
				for enumCase in scopeEnum.cases {
					switch enumCase.kind {
					case let .place(sites):
						for place in sites.compactMap(\.path.last) {
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
		private var formByKey = [SeamSignature.ScopeEnum.Key: DependencyTreeGenerator.BuilderForm]()
		private var ownPlacesByKey = [SeamSignature.ScopeEnum.Key: [PlaceSpelling: Property]]()
		private var levelsTakingSendableBuilder: Set<SeamSignature.ScopeEnum.Key>?
	}

	/// The builder struct of `scopeEnum`, `__safeDI_Builder<Built>`, or a seam's carrier, indented by `indent`: one stored
	/// function per case, its member, named as the case, which takes the struct the case's member takes
	/// (`ScopeEnum.Case.memberValuesTypeName`) and returns what the place builds – for a place held in an instantiator, the
	/// erased wrapper's `Builder` over what the place forwards, `()` for nothing, since the constrained wrappers cannot be
	/// spelled over `Built` – or the builder struct of the enum the case holds; and the memberwise initializer. A public
	/// mock's struct also declares `init(__safeDI_noScope:)` (`declaresLevelsWithoutScope`), which makes every member call one
	/// builder (`LevelsWithoutScope`). A `@Sendable` enum's struct is `Sendable`, with `@Sendable` members.
	private static func builderStructDeclaration(
		of scopeEnum: SeamSignature.ScopeEnum,
		levelForms: inout LevelBuilderForms,
		declaresLevelsWithoutScope: Bool,
		calledRootsTakingValue: Set<SeamSignature.ScopeEnum.Key>,
		typesDeclaredEscaping: Set<TypeDescription>,
		carrierValues: SeamCarrierValues,
		indent: String,
	) -> String {
		let carrierName = ReservedName.seamCarrier(ofEnum: scopeEnum.type)?.name
		let isSendable = scopeEnum.key.isSendable
		let memberIndent = indent + standardIndent
		let bodyIndent = memberIndent + standardIndent
		let sendableAttribute = isSendable ? "@Sendable " : ""
		let builtTypeName = ReservedName.builderStructGenericParameterName
		let builtType = TypeDescription.simple(name: builtTypeName, generics: [])
		var members = [(name: String, type: String, isLetChild: Bool)]()
		for enumCase in scopeEnum.cases {
			let returnType = LevelsWithoutScope.memberReturnType(of: enumCase, inSendableEnum: isSendable, built: builtType).asSource
			if carrierName != nil {
				// A carrier's member takes the values its level binds before the case's property, in field order: a deferred
				// parameter's as its memo, which a fill reads the instance of where its tree reads the value.
				let fields = enumCase.values?.fields ?? []
				let use = SeamCarrierValues.level(ofEnum: scopeEnum.type).map { carrierValues.use(ofLevel: $0, count: fields.count) }
				var parameters = use?.structType(qualifiedBy: nil).map { [$0.asSource] } ?? []
				parameters += fields[(use?.extras ?? 0..<fields.count)].map { field in
					(field.memoType ?? field.property.typeDescription.asFunctionParameter(amongTypesDeclaredEscaping: typesDeclaredEscaping)).asSource
				}
				if enumCase.isLetChildOfCarrier(inSendableEnum: isSendable) {
					// A level the member hands no value, outside every loop of levels: the carrier holds the child carrier itself,
					// formed where this carrier is formed.
					members.append((enumCase.name, returnType, true))
				} else {
					members.append((enumCase.name, "\(sendableAttribute)(\(parameters.joined(separator: ", "))) -> \(returnType)", false))
				}
			} else {
				members.append((enumCase.name, "\(sendableAttribute)(\(enumCase.memberValuesTypeName ?? "")) -> \(returnType)", false))
			}
		}
		var lines = [
			"\(indent)/// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.",
			carrierName.map { "\(indent)nonisolated public final class \($0)<\(builtTypeName)>\(isSendable ? ": Sendable" : "") {" }
				?? "\(indent)nonisolated public struct \(ReservedName.builderStructTypeName)<\(builtTypeName)>\(isSendable ? ": Sendable" : "") {",
		]
		// A member is named as its case, which is a label, so it is declared as a member's name is spelled: `Type` and
		// `Protocol` in backticks. No case is named `self`, which the memberwise initializer's parameter would hide the
		// instance behind: the macro requires an initializer parameter named as each dependency, and no initializer can
		// assign a property from a parameter named `self`.
		for member in members {
			lines.append("\(memberIndent)public let \(member.name.spelledAsMemberDeclarationName): \(member.type)")
		}
		lines.append("")
		lines.append("\(memberIndent)public init(\(members.map { "\($0.name): \($0.isLetChild ? "" : "@escaping ")\($0.type)" }.joined(separator: ", "))) {")
		for member in members {
			lines.append("\(bodyIndent)self.\(member.name) = \(member.name)")
		}
		lines.append("\(memberIndent)}")
		if declaresLevelsWithoutScope {
			// Only a call of a public mock calls this initializer, in this module or in one that calls the mock, which this
			// module cannot see.
			let builderParameter = ReservedName.noScopeParameterName
			let arguments = LevelsWithoutScope.memberArgumentsWithoutScope(
				of: scopeEnum,
				levelForms: &levelForms,
				calledRootsTakingValue: calledRootsTakingValue,
				carrierValues: carrierValues,
				builder: builderParameter,
				building: { _, builder in ".init(\(ReservedName.noScopeArgumentLabel): \(builder))" },
				buildingCalledRoot: { _, takesValue, fillLevel in ".init(\(ReservedName.noScopeArgumentLabel): { \(takesValue ? "_ in " : "")\(fillLevel) })" },
			)
			lines.append("")
			lines.append("\(memberIndent)public \(carrierName == nil ? "" : "convenience ")init(\(ReservedName.noScopeArgumentLabel) \(builderParameter): @escaping \(LevelsWithoutScope.builderType(ofLevel: scopeEnum.key, levelForms: &levelForms).asSource)) {")
			lines.append("\(bodyIndent)self.init(\(arguments.joined(separator: ", ")))")
			lines.append("\(memberIndent)}")
		}
		lines.append("\(indent)}")
		return lines.joined(separator: "\n")
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
		// Where a test observes fills, the function's lines up to its tree are spelled again from the fill's record alone.
		func observe(_ written: [String], form: FillSignature.Form, bound: [FillSignature.BoundValue] = [], parameters: [SeamSignature.Hole.Field] = []) {
			guard let observer = FillSignatureObservation.observer else { return }
			let record = FillSignature(
				hole: hole,
				functionNameStem: Self.fillFunctionName(of: hole),
				isSendable: isSendable,
				form: form,
				bound: bound,
				parameters: parameters,
				labelsReadOrDeclared: labelsReadInFill,
				returnsBoundValue: property.propertyType.isConstant,
			)
			observer(FillSignatureObservation(written: written, spelledFromRecord: record.spelledSignature(functionName: functionName, indent: indent, typesDeclaredEscaping: typesDeclaredEscaping)))
		}
		let childCode = try await generateProperties(
			codeGeneration: codeGeneration,
			propertiesGeneratedLater: fillBodyPropertiesGeneratedLater(propertiesGeneratedLater),
			enclosingFunctionNames: enclosingFunctionNames,
			leadingMemberWhitespace: indent,
			fillPlaceBindings: fillPlaceBindings,
		)
		// A caller's own value the fill reads from its mock root's binding is bound under its label from the name the root binds
		// it under, where that is not the label.
		var body = fillCallerReads.mockRootRebindings(rootBindingNames: fillPlaceBindings.rootBindingNames).map { "\(indent)let \($0.label) = \($0.rootBindingName)" }
		// A fill is hosted as its text until fills are planned (`.claude/rules/emission-decisions.md`).
		body += GeneratedCodeText.lines(of: GeneratedCode.lines(childCode).spelled())
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
			let header = "\(Self.localFunctionPrefix(isSendable: isSendable))func \(functionName)(\(parameters.joined(separator: ", "))) -> \(builderType.asSource) {"
			observe([header], form: .wrapperBuilder(parameters: fillMemberParameterFields, innerScopeLabels: innerScopeLabels))
			return ([header]
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
			let payloadFields = fillMemberParameterFields(takingPayloadFields: true)
			let parameters = payloadFields.map { "\($0.property.label.spelledAsArgumentLabel): \($0.property.typeDescription.asFunctionParameter(amongTypesDeclaredEscaping: typesDeclaredEscaping).asSource)" }
			let header = "\(Self.localFunctionPrefix(isSendable: isSendable))func \(functionName)(\(parameters.joined(separator: ", "))) -> \(hole.builtType.asSource) {"
			observe([header], form: .payloadFields(parameters: payloadFields))
			return ([header]
				+ body
				+ ["}"]).joined(separator: "\n")
		}
		// A fill of a place nested by type binds what its case's payload holds, and takes what a type further out binds.
		let nestedByTypeValues = hole.enumPlace?.values
		let valuesType = hole.valuesType(qualifiedBy: hole.scopeSeamType)
		// A deferred parameter's field the fill binds from the struct is bound as its memo (`bindingItsMemo`).
		let memoBoundLabels = Set(fillFields.filter(\.bindsMemo).map(\.property.label))
		// A seam's carrier hands the fill the case's values as arguments, each named as the payload's name joined with its label.
		let takesValuesAsArguments = if case let .nested(_, enumType, _)? = valuesType {
			ReservedName.seamCarrier(ofEnum: enumType) != nil
		} else {
			false
		}
		let caseValues = nestedByTypeValues ?? hole.fields
		let boundValues: [FillSignature.BoundValue] = valuesType == nil ? [] : caseValues.enumerated().filter { isRead($0.element) }.map { index, field in
			FillSignature.BoundValue(index: index, field: field, bindsMemo: memoBoundLabels.contains(field.property.label))
		}
		let bindings = boundValues.map { boundValue -> String in
			let (index, field, bindsMemo) = (boundValue.index, boundValue.field, boundValue.bindsMemo)
			let read = if let fillCarrierUse, takesValuesAsArguments {
				// The struct of the run the values end holds the field, unless it is one taken after it.
				fillCarrierUse.read(ofFieldAt: index, of: caseValues, inPayloadNamed: scopeParameterName, bindingMemo: bindsMemo)
			} else if takesValuesAsArguments {
				SeamHoles.argumentRead(of: field, inPayloadNamed: scopeParameterName, bindingMemo: bindsMemo)
			} else {
				"\(scopeParameterName).\(field.memberName(bindingMemo: bindsMemo))"
			}
			return "\(indent)let \(field.property.label) = \(read)"
		}
		// A fill of an instantiator's place returns the wrapper's builder (`fillReturnsWrapperBuilder`), so no fill here takes
		// a forwarded value.
		var parameters: [String] = if let fillCarrierUse, takesValuesAsArguments {
			zip(fillCarrierUse.parameterNames(of: caseValues, inPayloadNamed: scopeParameterName), fillCarrierUse.parameterTypes(of: caseValues, qualifiedBy: hole.scopeSeamType, typesDeclaredEscaping: typesDeclaredEscaping)).map { "_ \($0): \($1.asSource)" }
		} else if takesValuesAsArguments {
			caseValues.map { "_ \(SeamHoles.argumentName(of: $0, inPayloadNamed: scopeParameterName)): \(($0.memoType ?? $0.property.typeDescription.asFunctionParameter(amongTypesDeclaredEscaping: typesDeclaredEscaping)).asSource)" }
		} else {
			valuesType.map { ["_ \(scopeParameterName): \($0.asSource)"] } ?? []
		}
		parameters += fillParameterFields.map { "\($0.property.label.spelledAsArgumentLabel): \($0.boundTypeAsFunctionParameter(amongTypesDeclaredEscaping: typesDeclaredEscaping).asSource)" }
		let header = "\(Self.localFunctionPrefix(isSendable: isSendable))func \(functionName)(\(parameters.joined(separator: ", "))) -> \(hole.builtType.asSource) {"
		let form: FillSignature.Form = if let fillCarrierUse, takesValuesAsArguments {
			.carrierUse(fillCarrierUse)
		} else if takesValuesAsArguments {
			.caseArguments
		} else {
			.caseValues(valuesType: valuesType)
		}
		observe([header] + bindings, form: form, bound: boundValues, parameters: fillParameterFields)
		return ([header]
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
				// A seam's root body plans its children at once, as a root of the dependency tree does, where its module plans
				// few trees (`ConcurrentChildCode`).
				let generatedProperties = try await ConcurrentChildCode.$plansChildrenAtOnce.withValue(ConcurrentChildCode.seamRootsPlanChildrenAtOnce) {
					try await generateProperties(
						propertiesGeneratedLater: propertiesGeneratedLater,
						enclosingFunctionNames: builderFunctionNames.enclosingFunctionNames,
						leadingMemberWhitespace: bodyIndent,
						fillPlaceBindings: fillPlaceBindings,
					)
				}
				// A test that observes node records compares this body with theirs.
				NodeRecordsObservation.rootBodyObserver?(generatedProperties)
				let argumentList = try instantiable.generateArgumentList(
					unavailableProperties: unavailableProperties,
				)
				// A seam lays its body out by the type key, as a root does, reading its parameters and builders as the
				// declarations before the body. A deferred parameter is read through its memo, bound under its label.
				var outerDeclarations = signature.parameters.map { parameter in
					guard case let .deferred(isSendable) = parameter.deferral, autoclosureCallByLabel[parameter.property.label] == nil else { return parameter.property }
					return Property(label: parameter.property.label, typeDescription: .simple(name: isSendable ? Dependency.sendableLazilyInstantiatedType : Dependency.lazilyInstantiatedType, generics: [parameter.property.typeDescription]))
				}
				outerDeclarations.append(contentsOf: signature.builders.map { Property(label: $0.internalName, typeDescription: $0.parameterType) })
				let layout = TypeKeyBody.statements(
					ofRootBody: generatedProperties,
					outerDeclarations: outerDeclarations,
					namesInScope: Set(signature.parameters.map(\.internalName) + signature.builders.map(\.internalName)),
				)
				var bodyLines = memoLines
				let bodyStatements = layout ?? RootFunctionHoisting.hoisted(generatedProperties, indentation: bodyIndent)
				if !bodyStatements.isEmpty {
					bodyLines.append(GeneratedCode.lines(bodyStatements).spelled())
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
				// A builder that takes nothing is handed to the generated-only initializer as the levels of its builder, every member
				// of which calls it, built by functions the initializer declares (`LevelsWithoutScope`).
				var levelsWithoutScope = LevelsWithoutScope(scopeEnums: signature.scopeEnums)
				var bodyLines = levelsWithoutScope.functionDeclarations(reachedFrom: signature.builders.map(\.enumKey), indent: bodyIndent)
				let forwardedArguments = parameters.map { "\($0.generatedOnlyArgumentLabel): \($0.property.label)" }
					+ signature.builders.map { builder in
						"\(builder.generatedOnlyArgumentLabel(inTierAt: tier)): \(levelsWithoutScope.call(ofLevel: builder.enumKey, handing: builder.label(inTierAt: tier)))"
					}
				bodyLines.append("\(bodyIndent)self.init(\(forwardedArguments.joined(separator: ", ")))")
				initializers.append("""
				\(marker ?? "")\(plainDocumentation)
				\(declarationPrefix)(\(plainParameterList(of: parameters, inTierAt: tier))) {
				\(bodyLines.joined(separator: "\n"))
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
			declaresLevelsWithoutScope: false,
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
	static func aliasDeclaration(
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
	static func referencingDeclaration(
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

	// MARK: Mock Root Parameters

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
		/// The names of the mock's tree the parameters were classified from.
		let treeNames: MockTreeNames
		/// The name of each child the mock root builds, by label and property type: its label,
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
		/// The received properties every receiver receives only if available and nothing in the mock provides, and
		/// `unavailableDependencyOverrideProperties`.
		let onlyIfAvailableReceivedProperties: [Property]
		/// The properties instantiated only if available that nothing fulfills (`MockTreeNames.unavailableDependencyProperties`)
		/// that `mock()` takes an override of, which the type that declares one binds it from: each but one of the label and
		/// type of a value `mock()` already takes, which stays `nil`, since that value is another declaration's.
		let unavailableDependencyOverrideProperties: Set<Property>
		/// For an internal mock, those of `onlyIfAvailableReceivedProperties` that only the calls of other modules' public mocks
		/// in its tree receive, whose overrides are named apart from the builders and the flat received parameters. Empty for a
		/// public mock, which takes them as parameters that the others are named apart from.
		let onlyIfAvailableReceivedPropertiesOnlyPublicMockCallsReceive: Set<Property>
		/// The `@Instantiated` dependencies, of the mocked type and of the types in its tree, that no node builds, but those a
		/// builder of `seamMockBuilders` builds.
		let flatUncoveredParameters: [UncoveredParameter]
		/// The `@Instantiated` dependencies, of the mocked type and of the types in its tree, that no node builds, each named.
		let uncoveredParameters: [UncoveredParameter]
		/// For the internal mock of a type that generates its dependency tree, the builders `mock()` takes in place of the
		/// parameters of the places they build (`ScopeGenerator.seamMockBuilders(of:otherParameterLabels:builderFunctionNames:namesBoundInTheTree:)`).
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
			/// The builders of the tree's calls of other modules' public mocks of this builder's hole type and family whose
			/// places a call fills (`FilledCall`), in the order the calls are generated: each call hands the called builder's
			/// struct from this builder, or, where `mock()` takes it optional and is passed `nil`, from its fills.
			var filledCallBuilders = [FilledCallBuilder]()
			/// Whether `mock()` takes the builder optional, `= nil`: a call fills every place of its hole type and family, and
			/// keeps its fills where the builder is `nil`.
			var isOptional = false

			/// A builder of a call of another module's public mock whose places the call fills.
			struct FilledCallBuilder {
				/// The generator of the call.
				let call: ObjectIdentifier
				/// The called builder's label.
				let label: String
			}

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
				let calledBuilders: [(builder: SeamSignature.Builder, calledBuilders: CalledBuilders)]

				/// The properties of the places the called builders reach, in the order of the calls and of each called mock's
				/// holes, which decide, with the mock's own places, the form of a builder that takes the calls' builders where
				/// they pass it up in other forms.
				var placeProperties: [Property] {
					calledBuilders.flatMap { called in
						called.calledBuilders.holesOfItsHoleTypeReached(by: called.builder).map(\.property)
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

	/// A call of another module's public mock in an internal mock's tree, at the mock root's level or inside a fill, with
	/// whether it is made inside a `@Sendable` function (`fillPlaces(insideSendableFunction:)`). Each builder whose places it
	/// fills is of the family of its hole type that a builder the call passed up would be of: the
	/// `@Sendable` one where the called builder is or the call is made inside a `@Sendable` function, which captures it.
	struct FilledCall {
		let generator: ScopeGenerator
		let isInsideSendableFunction: Bool
		/// The calls whose fills hold this call, nearest first, one of which a call that re-enters an enclosing call's level
		/// function re-enters (`reenteredBuilders`).
		let enclosingCalls: [ScopeGenerator]

		/// Each builder the call fills a place of, with its family, in the order the call passes them.
		var filledBuilders: [(builder: SeamSignature.Builder, family: MockRootParameters.SeamMockBuilder.Family)] {
			guard let publicMockCall = generator.publicMockCall else { return [] }
			return generator.builderCallArguments.compactMap { argument in
				guard argument.builderStruct?.rootDispatcherKey != nil,
				      let builder = publicMockCall.builders.first(where: { $0.label == argument.label })
				else { return nil }
				return (builder, MockRootParameters.SeamMockBuilder.Family(holeType: builder.enumKey.holeType, isSendable: builder.enumKey.isSendable || isInsideSendableFunction))
			}
		}

		/// Each builder the call passes the level function of an enclosing call's builder, re-entering it, with the nearest
		/// enclosing call that passes that function and its label there: the call passes what the enclosing call passes.
		var reenteredBuilders: [(label: String, enclosingCall: ScopeGenerator, enclosingLabel: String)] {
			generator.builderCallArguments.compactMap { argument in
				guard argument.builderStruct == nil, let enclosingFill = argument.enclosingFill else { return nil }
				for enclosingCall in enclosingCalls {
					if let enclosingArgument = enclosingCall.builderCallArguments.first(where: { $0.builderStruct?.rootDispatcherKey == enclosingFill.key }) {
						return (argument.label, enclosingCall, enclosingArgument.label)
					}
				}
				return nil
			}
		}
	}

	/// The bindings of the places inside the fills an internal mock declares (`FillPlace`), by the generator of the type
	/// that instantiates them, in the order the type declares them: each calls the builder `mock()` takes for the place's
	/// hole type and family, once per build of the type.
	/// Also the names a mock root binds received values under apart from their labels.
	struct FillPlaceBindings: Hashable {
		init(bindingsByGenerator: [ObjectIdentifier: [SendableAutoclosureParameter]], rootBindingNames: [String: [TypeDescription: String]] = [:], holeBuildersByCall: [ObjectIdentifier: [String: HoleBuilder]] = [:], holeBuildersByInlinePlace: [ObjectIdentifier: HoleBuilder] = [:]) {
			self.bindingsByGenerator = bindingsByGenerator
			self.rootBindingNames = rootBindingNames
			self.holeBuildersByCall = holeBuildersByCall
			self.holeBuildersByInlinePlace = holeBuildersByInlinePlace
		}

		let bindingsByGenerator: [ObjectIdentifier: [SendableAutoclosureParameter]]
		/// For each call of another module's public mock in the mock's tree, by its generator, the builder `mock()` takes for
		/// each called builder whose places the call fills, by the called builder's label (`SeamMockBuilder.filledCallBuilders`).
		let holeBuildersByCall: [ObjectIdentifier: [String: HoleBuilder]]
		/// For each place of a type another module generates a public mock for that the mock builds inline, rather than
		/// calling that mock, whose type the declaring module sees nothing fulfill, by its node, the builder `mock()` takes
		/// for the place's hole type and family, which the place reads as a call of that public mock would
		/// (`ScopeGenerator.holeBuildersByInlinePlace(in:buildersByFamily:foreignPublicMocks:)`).
		let holeBuildersByInlinePlace: [ObjectIdentifier: HoleBuilder]

		/// The builder `mock()` takes for the places of one called builder a call fills.
		struct HoleBuilder: Hashable {
			/// The name the body calls the builder by.
			let name: String
			/// Whether `mock()` takes it optional, the call's fills building the places where it is `nil`.
			let isOptional: Bool

			/// What the call passes the called builder, given `fillsStruct`, the struct its fills make: the struct of this
			/// builder, or of the fills where an optional builder is `nil`.
			func structValue(fillsStruct: String) -> String {
				// No call of a builder that takes a value fills a place the builder of a plain place fills too: a place whose
				// builder takes a value is an instantiator of a type that conforms to `Instantiable` by hand, which no type a
				// caller declares can fulfill, since it would declare that conformance again, so no adapter is needed.
				isOptional
					? "\(name).map { .init(\(ReservedName.noScopeArgumentLabel): $0) } ?? \(fillsStruct)"
					: ".init(\(ReservedName.noScopeArgumentLabel): \(name))"
			}

			/// What an override closure of the call is handed for the called builder, given `fillsCall`, the call of the
			/// call's fill: a closure that calls this builder, or the fill where an optional builder is `nil`.
			func overrideValue(fillsCall: String) -> String {
				isOptional
					? "{ if let \(name) { \(name)() } else { \(fillsCall) } }"
					: "{ \(name)() }"
			}

			/// What an override closure of the call is handed for a called builder of a wrapper whose place forwards a value,
			/// given `fillsCall`, the call of the call's fill, which returns the wrapper's builder: this builder, or the fill's
			/// where an optional builder is `nil`.
			func wrapperBuilderValue(fillsCall: String) -> String {
				isOptional
					? "\(name) ?? \(fillsCall)"
					: name
			}

			/// What a place of a public mock built inline is bound to, given `construction`, the expression that builds it
			/// otherwise, which reads `overrideExpression`, the place's own override, where it has one: this builder's value
			/// where no override is set, as a call of the public mock hands the place the builder, and `construction` where
			/// one is, or where an optional builder is `nil`. A place held in a wrapper, `wrapperType`, is the wrapper made
			/// of this builder, which takes what the wrapper forwards.
			func inlinePlaceValue(construction: String, overrideExpression: String?, wrappingBuilderIn wrapperType: String? = nil) -> String {
				var conditions = [String]()
				if isOptional {
					conditions.append("let \(name)")
				}
				if let overrideExpression {
					conditions.append("\(overrideExpression) == nil")
				}
				let value = if let wrapperType {
					"\(wrapperType)(\(name))"
				} else {
					"\(name)()"
				}
				guard !conditions.isEmpty else { return value }
				let otherwise = construction.hasPrefix("if ") ? construction : "{ \(construction) }"
				return "if \(conditions.joined(separator: ", ")) { \(value) } else \(otherwise)"
			}
		}

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

	/// Those of `onlyIfAvailableReceivedProperties` that are among `receivedOnlyByPublicMockCalls`, each matched by the value
	/// it stands for, since a mock spells each as the most explicit of its receivers' spellings and takes a lazily received
	/// one as its instance.
	static func onlyIfAvailableReceivedProperties(_ onlyIfAvailableReceivedProperties: [Property], receivedOnlyBy receivedOnlyByPublicMockCalls: Set<Property>) -> Set<Property> {
		let receivedOnlyByPublicMockCallsByValue = Set(receivedOnlyByPublicMockCalls.map(\.asValidatedForDependencyCycles.asUnwrappedProperty))
		var properties = Set<Property>()
		for property in onlyIfAvailableReceivedProperties where receivedOnlyByPublicMockCallsByValue.contains(property.asValidatedForDependencyCycles.asUnwrappedProperty) {
			properties.insert(property)
		}
		return properties
	}

	/// The properties only the calls of other modules' public mocks in a mock's tree receive that the mock takes no
	/// parameter or override for: those every call omits. A mock takes each a call passes, a public mock as a parameter
	/// and an internal one as an override, but an internal mock leaves out one whose label `labelsReadInsideSendableFunctions`
	/// holds.
	static func receivedOnlyByPublicMockCallsLeftOut(receivedOnlyByPublicMockCalls: Set<Property>, passedByPublicMockCalls: Set<Property>, labelsReadInsideSendableFunctions: Set<String>) -> Set<Property> {
		var leftOut = receivedOnlyByPublicMockCalls.subtracting(passedByPublicMockCalls)
		for property in passedByPublicMockCalls where labelsReadInsideSendableFunctions.contains(property.label) {
			leftOut.insert(property)
		}
		return leftOut
	}

	/// For an internal mock, the labels among `passedByPublicMockCalls` that a receiver in its tree reads inside a `@Sendable`
	/// function (`labelsReadInsideSendableFunction(among:)`), such as a call of another module's public mock, where the
	/// override a mock binds above it would be captured, which compiles only for a `Sendable` value: the mock takes no
	/// override for such a value, and the calls pass `nil`, as production passes `nil` where nothing provides it. Empty for a
	/// public mock, which takes each as a parameter.
	///
	/// A deliberate gap from the inline mock and the public mock, which take such a value, as an override or a parameter
	/// that does not compile where the value is not `Sendable`. The other site of the gap is the mock root's walk in
	/// `DependencyTreeGenerator.createMockRootScopeGenerator`.
	nonisolated func passedByPublicMockCallLabelsReadInsideSendableFunctions(of instantiable: Instantiable) -> Set<String> {
		guard instantiable.generateMock != .public, !passedByPublicMockCalls.isEmpty else { return [] }
		return labelsReadInsideSendableFunction(among: Set(passedByPublicMockCalls.map(\.label)))
	}

	/// The names of the flat parameters of a public mock root with `parameters`; the lowering names an internal mock's
	/// (`MockLowering.lowerRootSignature`).
	static func mockRootParameterNames(of parameters: MockRootParameters) -> MockRootParameterNames {
		let treeProperties = parameters.treeNames.rootProperties
		let namesDeclaredInBuilderFunctions = parameters.treeNames.namesDeclaredInBuilderFunctions
		let treeBindingNames = Self.bindingNames(of: treeProperties, labels: Set(treeProperties.map(\.label)), labelMap: parameters.rootLabelMap)
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
			+ parameters.onlyIfAvailableReceivedProperties.filter { !parameters.onlyIfAvailableReceivedPropertiesOnlyPublicMockCallsReceive.contains($0) }.map(\.label)
		// Map of (label → (type → disambiguatedLabel)) for flat received
		// parameters whose label collided with another flat parameter. Builder calls
		// for child nodes that would reference the original label must substitute
		// the disambiguated name so the generated code references a real binding.
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
		)
		let onlyIfAvailableOverrides: [OnlyIfAvailableOverride] = if parameters.onlyIfAvailableReceivedProperties.isEmpty {
			[]
		} else {
			// A public mock takes what only its calls receive as parameters of its own, so it takes no override named after
			// the others (`onlyIfAvailableReceivedPropertiesOnlyPublicMockCallsReceive` is empty).
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
	/// A deliberate gap, commented where the closure types are built (`MockLowering.ConstantNode.builderClosureType`) and where the arguments are
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
		// receive of the label makes the mock bind, as it reads that declaration (`NearestDeclarations.resolvingBinding(of:)`): the
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
		let treeProperties = parameters.treeNames.rootProperties
		var siblingDisambiguationMap = [String: [TypeDescription: String]]()
		for property in treeProperties {
			if let disambiguated = parameters.rootLabelMap[property.label]?[property.typeDescription], disambiguated != property.label {
				siblingDisambiguationMap[property.label, default: [:]][property.typeDescription] = disambiguated
			}
		}
		// The root's own aliases are bound in the same scope as the dependencies promoted
		// to the root and the `onlyIfAvailable` override bindings. Bind an alias whose label
		// one of those already binds under a name of its own, and pass that name to the root
		// and to the alias's receivers in the tree.
		let treePropertyNodeBindingNames = Set(treeProperties.map { property in
			siblingDisambiguationMap[property.label]?[property.typeDescription] ?? property.label
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
	/// What the classification of a mock root's parameters (`mockRootParameters(instantiable:mockDefaults:treeNames:)`)
	/// reads of the mock's tree: the names it binds and declares, and the `@Instantiated` dependencies no node builds.
	struct MockTreeNames {
		/// An `@Instantiated` dependency of the mocked type or of a type of its tree that the mock cannot build.
		struct UncoveredDependency {
			/// The dependency, as the first type to instantiate it declares it.
			let dependency: Dependency
			/// Whether a builder function around a type passed it declares its label.
			let isHiddenWhereReferenced: Bool
			/// Whether a type built inside a `@Sendable` builder function instantiates it.
			let isInstantiatedInSendableFunction: Bool
			/// The types that create it: the mocked type, then the types of its tree depth first, each type's children in the
			/// order it declares them, each type once.
			let creatingTypes: [TypeDescription]
		}

		/// The properties of the property nodes at the root's level, in order.
		let rootProperties: [Property]
		/// The `@Instantiated` dependencies of the mocked type that the mock cannot build, in its declaration order.
		let mockedTypeUncoveredDependencies: [Dependency]
		/// The `@Instantiated` dependencies the mock cannot build, each once by property: the mocked type's, then each type's
		/// in the order a walk of the tree in generation order first meets them.
		let uncoveredDependencies: [UncoveredDependency]
		/// The labels of the dependencies of every node of the tree, which its builder functions declare.
		let namesDeclaredInBuilderFunctions: Set<String>
		/// The names of the builder functions of every node of the tree.
		let builderFunctionNames: Set<String>
		/// The properties the mocked type and the types of its tree instantiate only if available that nothing fulfills, each
		/// once, in the order a walk of the tree in generation order first meets them. One a type built inside a `@Sendable`
		/// builder function declares is left out: it is bound to `nil` there, since the function could not capture an override.
		var unavailableDependencyProperties = [Property]()
		/// The places inside the fills of the tree's calls of other modules' public mocks (`FillPlace`), in the order the calls
		/// are generated, each a place of a builder `mock()` takes. The query and a public mock's promotion read a tree that
		/// holds no internal mock's call, so their names leave these four empty (`treeNames(of:readsFills:)`).
		var fillPlaces = [FillPlace]()
		/// The labels the types of those fills' trees declare.
		var namesDeclaredInFills = Set<String>()
		/// The calls of other modules' public mocks that fill builders, at the root's level or inside fills (`FilledCall`).
		var filledCalls = [FilledCall]()
		/// The family of each builder the tree's calls pass up, by the property each call's leaf receives it as.
		var passedUpBuilderFamilies = [Property: MockLowering.PassedUpBuilderFamily]()
		/// Every node of the tree that builds a type, a node that closes a cycle included, each before its children, depth
		/// first in generation order.
		var propertyNodes = [PropertyNode]()
		/// The properties the sites of holes at the root's level bind, in generation order.
		var rootHoleSiteProperties = [Property]()

		/// A node of the mock's tree that builds a type: what it builds, and where it is in the tree.
		struct PropertyNode {
			/// The index in `propertyNodes` of the node whose type declares this node's property, or `nil` for a node at the
			/// root's level.
			let parentIndex: Int?
			let property: Property
			/// The declaration the node builds its type from.
			let instantiable: Instantiable
			let erasedToConcreteExistential: Bool
			/// Whether the node closes a cycle, so it builds nothing beneath it.
			let isPropertyCycle: Bool
			/// The node's generator.
			let generator: ScopeGenerator
			/// Whether the node is built inside a `@Sendable` builder function: its own, or one around it.
			let isInsideSendableFunction: Bool

			/// Whether the node builds its type with the type's hand-written mock: where the mock returns the type the
			/// property builds, as `MockConstruction` decides it.
			var usesMockInitializer: Bool {
				instantiable.mockReturnTypeIsCompatible(withPropertyType: property.typeDescription.asInstantiatedType)
			}
		}
	}

	/// The parameters of the mock of `instantiable`, classified from the names of its tree without its calls' fills or
	/// passed-up builders (`treeNames(of:readsFills:)`), which every reader but the mock's own lowering reads.
	func mockRootParameters(instantiable: Instantiable, mockDefaults: [TypeDescription: FlatParameterMockDefault]) -> MockRootParameters {
		mockRootParameters(instantiable: instantiable, mockDefaults: mockDefaults, treeNames: treeNames(of: instantiable, readsFills: false).names)
	}

	/// The parameters of the mock of `instantiable`, classified from what its tree receives and from `treeNames`.
	func mockRootParameters(
		instantiable: Instantiable,
		mockDefaults: [TypeDescription: FlatParameterMockDefault],
		treeNames: MockTreeNames,
	) -> MockRootParameters {
		// A public mock another module generated builds what its call does not pass, so `mock()` takes no parameter or
		// override for what every such call omits. It takes what the calls pass, as a receive only if available that
		// defaults to `nil`: a public mock as a parameter, so that its own callers can hand one instance down the chain, and
		// an internal mock as an override, as it takes its own tree's.
		let receivedOnlyByPublicMockCallsLeftOut = Self.receivedOnlyByPublicMockCallsLeftOut(
			receivedOnlyByPublicMockCalls: receivedOnlyByPublicMockCalls,
			passedByPublicMockCalls: passedByPublicMockCalls,
			labelsReadInsideSendableFunctions: passedByPublicMockCallLabelsReadInsideSendableFunctions(of: instantiable),
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
		let treeProperties = treeNames.rootProperties
		let treePropertyLabels = Set(treeProperties.map(\.label))
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
					&& treeProperties.contains { $0.label == property.label && $0.typeDescription == .optional(property.typeDescription) })
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
		let mockedTypeUncoveredDependencies = treeNames.mockedTypeUncoveredDependencies
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
		// A property instantiated only if available that nothing fulfills takes an override too, which defaults to `nil`, the
		// value production binds. The type that declares it binds it from the override, so it reads no declaration above it.
		// A public mock takes a builder for it instead, as a seam does, which a module that calls the mock and sees a
		// declaration that fulfills the type fills at each place; one spelled as no hole can be stays `nil` there.
		var unavailableDependencyOverrideProperties = Set<Property>()
		for property in treeNames.unavailableDependencyProperties
			where instantiable.generateMock != .public
			&& !receivedParameterProperties.contains(property)
			&& !receivedParameterProperties.contains(property.asUnwrappedProperty)
			&& !isFulfilledByForwardedProperty(property)
		{
			unavailableDependencyOverrideProperties.insert(property)
			onlyIfAvailableReceivedProperties.append(property)
		}
		if !unavailableDependencyOverrideProperties.isEmpty {
			onlyIfAvailableReceivedProperties.sort(by: { $0.precedesInMockOrder($1) })
		}
		// A received dependency the mock cannot build defaults to the hand-written mock its type has, as a forwarded one does.
		var flatReceivedParameterMockDefaults = [Property: FlatParameterMockDefault]()
		for property in flatReceivedProperties {
			flatReceivedParameterMockDefaults[property] = mockDefaults[property.typeDescription]
		}

		var uncoveredDependencies = UncoveredDependencies()
		for uncovered in treeNames.uncoveredDependencies {
			uncoveredDependencies.add(uncovered.dependency, isHiddenWhereReferenced: uncovered.isHiddenWhereReferenced, isInstantiatedInSendableFunction: uncovered.isInstantiatedInSendableFunction)
		}

		// Every name the mock root's scope generates – a binding of the tree, a parameter, or an override
		// named apart, a lazily instantiated wrapper, or an alias renamed – is referenced inside the builder
		// functions beneath it, so it is named apart from the names those functions declare, too. A
		// declaration there of a name the root's scope generates would hide the root's binding from the code
		// in that function, which would then read the declaration instead.
		let namesDeclaredInBuilderFunctions = treeNames.namesDeclaredInBuilderFunctions
		// A promoted dependency whose label a parameter that keeps its label has is named apart from it, since
		// its binding would hide the parameter from the mocked type and from the receivers of the parameter.
		let rootLabelMap = Self.disambiguatePropertyLabels(
			forProperties: treeProperties,
			besideParametersKeepingTheirLabels: parametersKeepingTheirLabels,
			reservedNames: namesDeclaredInBuilderFunctions,
		)
		let treeBindingNames = Self.bindingNames(of: treeProperties, labels: treePropertyLabels, labelMap: rootLabelMap)

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
		var creatingTypesByProperty = [Property: [TypeDescription]]()
		for uncovered in treeNames.uncoveredDependencies {
			creatingTypesByProperty[uncovered.dependency.property] = uncovered.creatingTypes
		}
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
		// (`FillPlace`), where its twin's fill calls the builder its seam takes. The query reads no module's public mocks, so
		// the tree it reads holds no call of one (`MockTreeNames.fillPlaces`).
		//
		// A deliberate gap from the production twin: an internal mock of a type that generates no dependency tree keeps a
		// flat parameter for each type its own tree instantiates that nothing fulfills, outside every fill, as for a seam it
		// builds itself whose hole nothing fills, where the twin takes the seam's builder: flat parameters are its API, and
		// its own tree passes one value per name. Inside a fill it takes a builder, as its twin does. The other site of the
		// gap is `fillPlaces(insideSendableFunction:)`.
		// An internal mock's override of a receive only if available that only the calls of other modules' public mocks in its
		// tree make is named apart from the builders and the flat received parameters, which keep their labels beside it
		// (`mockRootParameterNames(of:)`), so that taking the override renames no parameter of `mock()`.
		let onlyIfAvailableReceivedPropertiesOnlyPublicMockCallsReceive: Set<Property> = if instantiable.generateMock == .public || receivedOnlyByPublicMockCalls.isEmpty {
			[]
		} else {
			Self.onlyIfAvailableReceivedProperties(onlyIfAvailableReceivedProperties, receivedOnlyBy: receivedOnlyByPublicMockCalls)
		}
		let seamMockBuilders = instantiable.generateMock != .public
			? Self.seamMockBuilders(
				of: instantiable.generatesDependencyTree ? uncoveredParameters : [],
				fillPlaces: treeNames.fillPlaces,
				passedUpBuilders: treeNames.passedUpBuilderFamilies,
				otherParameterLabels: Set(forwardedDependencies.map(\.property.label))
					.union(rootDefaultParameters.map(\.label))
					.union(onlyIfAvailableReceivedProperties.lazy.filter { !onlyIfAvailableReceivedPropertiesOnlyPublicMockCallsReceive.contains($0) }.map(\.label))
					.union(instantiable.generatesDependencyTree ? [] : uncoveredParameters.map(\.label))
					.union([ReservedName.mockOverridesParameterName]),
				flatReceivedProperties: flatReceivedProperties,
				filledCalls: treeNames.filledCalls,
				typesDeclaredEscaping: typesDeclaredEscaping,
				builderFunctionNames: treeNames.builderFunctionNames,
				// The fills' labels name the builders apart only where a fill calls one; a builder `mock()` takes optional is
				// read by the calls inside fills too, so its name is apart from them whatever the fills call.
				namesBoundInTheTree: treeBindingNames.union(namesDeclaredInBuilderFunctions).union(treeNames.fillPlaces.isEmpty ? [] : treeNames.namesDeclaredInFills),
				namesBoundInTheFills: treeNames.namesDeclaredInFills,
			)
			: []
		let passedUpPropertiesBuiltBySeamMockBuilders = Set(seamMockBuilders.flatMap(\.passedUpProperties))
		flatReceivedProperties.removeAll { passedUpPropertiesBuiltBySeamMockBuilders.contains($0) }
		let builtProperties = Set(seamMockBuilders.flatMap(\.places).map(\.property))
		let flatUncoveredParameters = uncoveredParameters.filter { !builtProperties.contains($0.property) }

		return MockRootParameters(
			treeNames: treeNames,
			rootLabelMap: rootLabelMap,
			forwardedDependencies: forwardedDependencies,
			forwardedParameterDefaults: forwardedParameterDefaults,
			rootConstructionInitializer: rootConstructionInitializer,
			rootDefaultParameters: rootDefaultParameters,
			flatReceivedProperties: flatReceivedProperties,
			flatReceivedParameterMockDefaults: flatReceivedParameterMockDefaults,
			onlyIfAvailableReceivedProperties: onlyIfAvailableReceivedProperties,
			unavailableDependencyOverrideProperties: unavailableDependencyOverrideProperties,
			onlyIfAvailableReceivedPropertiesOnlyPublicMockCallsReceive: onlyIfAvailableReceivedPropertiesOnlyPublicMockCallsReceive,
			flatUncoveredParameters: flatUncoveredParameters,
			uncoveredParameters: uncoveredParameters,
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
		let parameters = mockRootParameters(instantiable: instantiable, mockDefaults: mockDefaults)
		return Set(parameters.publicMockWrapperParameterByInstance.keys.filter { instance in
			receivedProperties.contains(instance) || receivedProperties.contains(instance.asOptionalProperty)
		})
	}

	/// The calls of other modules' public mocks in the tree of `treePropertyNodes` and inside their fills
	/// (`fillPlaces(insideSendableFunction:)`), in the order the calls' nodes are generated, with every label the fills' trees
	/// declare.
	static func fillPlaces(in treePropertyNodes: [MockTreeNames.PropertyNode]) -> (declaredLabels: Set<String>, calls: [FilledCall]) {
		var declaredLabels = Set<String>()
		var calls = [FilledCall]()
		// The records are in generation order, each before its children. Only a node that calls a public mock fills a
		// builder (`fillsABuilder`).
		for node in treePropertyNodes where node.generator.fillsABuilder {
			let callPlaces = node.generator.fillPlaces(insideSendableFunction: node.isInsideSendableFunction)
			declaredLabels.formUnion(callPlaces.declaredLabels)
			calls.append(FilledCall(generator: node.generator, isInsideSendableFunction: node.isInsideSendableFunction, enclosingCalls: []))
			calls += callPlaces.calls
		}
		return (declaredLabels, calls)
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
	/// - Parameter passedUpBuilders: The family of each builder the calls pass up, by the property each call's leaf receives
	///   it as, with whether a `@Sendable` builder function captures it, which `mock()` takes `@Sendable`.
	private static func seamMockBuilders(
		of uncoveredParameters: [MockRootParameters.UncoveredParameter],
		fillPlaces: [FillPlace],
		passedUpBuilders: [Property: MockLowering.PassedUpBuilderFamily],
		otherParameterLabels: Set<String>,
		flatReceivedProperties: [Property],
		filledCalls: [FilledCall],
		typesDeclaredEscaping: Set<TypeDescription>,
		builderFunctionNames: Set<String>,
		namesBoundInTheTree: Set<String>,
		namesBoundInTheFills: Set<String>,
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
			passedUpBuilders[property]?.isCapturedBySendableFunction == true && !property.typeDescription.isSendableFunction ? property.typeDescription.asSendableBuilder : property.typeDescription
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
		// Each builder a call fills places of joins the builder of its family where the mock takes one; every other family is a
		// builder `mock()` takes optional, which replaces the calls' fills of its places where it is passed.
		let filledFamilies = Self.filledFamilies(of: filledCalls)
		guard !familiesInOrder.isEmpty || !filledFamilies.isEmpty else { return [] }
		let requiredFamilies = Set(familiesInOrder)
		let optionalFamilies = filledFamilies.filter { !requiredFamilies.contains($0.family) }
		var holeTypes = [SeamSignature.HoleType]()
		for family in familiesInOrder where !holeTypes.contains(family.holeType) {
			holeTypes.append(family.holeType)
		}
		let stems = DependencyTreeGenerator.stems(of: holeTypes)
		let optionalStems = Self.stemsOfOptionalBuilders(
			of: optionalFamilies.map { ($0.family.holeType, $0.receivedProperty) },
			besideOwnHoleTypes: familiesInOrder.filter { passedUpPropertiesByFamily[$0] == nil }.map(\.holeType),
			passedUpHoleTypes: familiesInOrder.compactMap { family in passedUpPropertiesByFamily[family]?.first.map { (family.holeType, $0) } },
			requiredStems: stems,
		)
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
				ofPlaceProperties: ownPlaceProperties + propertiesPassedUp.flatMap { passedUpBuilders[$0]?.placeProperties ?? [] },
				in: family,
			)
		}
		let passedUpProperties = Set(passedUpPropertiesByFamily.values.flatMap(\.self))
		var labels = GeneratedNameAllocator(reserving: otherParameterLabels.union(flatReceivedProperties.filter { !passedUpProperties.contains($0) }.map(\.label)))
		var builders = familiesInOrder.map { family in
			let stem = stems[family.holeType, default: ""]
			let label = labels.claim(family.isSendable ? DependencyTreeGenerator.sendableBuilderLabel(ofStem: stem) : DependencyTreeGenerator.plainBuilderLabel(ofStem: stem))
			var builder = MockRootParameters.SeamMockBuilder(label: label, internalName: label, family: family, places: placesByFamily[family, default: []], fillPlaces: fillPlacesByFamily[family, default: []], passedUpProperties: passedUpPropertiesByFamily[family, default: []], parameterType: parameterType(of: family))
			builder.filledCallBuilders = filledFamilies.first { $0.family == family }?.callBuilders ?? []
			return builder
		}
		// The optional builders claim their labels after every builder `mock()` took before, so none of those labels moves.
		for filled in optionalFamilies {
			let stem = optionalStems[filled.family.holeType, default: ""]
			let label = labels.claim(filled.family.isSendable ? DependencyTreeGenerator.sendableBuilderLabel(ofStem: stem) : DependencyTreeGenerator.plainBuilderLabel(ofStem: stem))
			var builder = MockRootParameters.SeamMockBuilder(label: label, internalName: label, family: filled.family, places: [], fillPlaces: [], passedUpProperties: [], parameterType: MockRootParameters.SeamMockBuilder.parameterType(ofPlaceProperties: filled.placeProperties, in: filled.family))
			builder.filledCallBuilders = filled.callBuilders
			builder.isOptional = true
			builders.append(builder)
		}
		builders.sort { $0.label < $1.label }
		// A builder whose label a name of the tree has is called by a name apart from every builder function of the tree.
		let namesBoundInTheTreeAndFills = namesBoundInTheTree.union(namesBoundInTheFills)
		var names = GeneratedNameAllocator(reserving: builderFunctionNames.union(namesBoundInTheTreeAndFills))
		for index in builders.indices where (builders[index].filledCallBuilders.isEmpty ? namesBoundInTheTree : namesBoundInTheTreeAndFills).contains(builders[index].label) {
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

	/// A family of hole type whose places the calls of other modules' public mocks in a mock's tree fill (`FilledCall`), with
	/// the calls' builders of it, the properties of the places they reach, and the property a call would receive the builder
	/// as if it passed it up, the first in sorted order, which orders the family's stem and label among the builders a call
	/// passes up.
	struct FilledFamily {
		let family: MockRootParameters.SeamMockBuilder.Family
		var callBuilders: [MockRootParameters.SeamMockBuilder.FilledCallBuilder]
		var placeProperties: [Property]
		var receivedProperty: Property
	}

	/// The families `filledCalls` fill places of, in the sorted order of the properties the calls would receive their
	/// builders as (`FilledFamily.receivedProperty`), as a lifted gate would pass them up.
	static func filledFamilies(of filledCalls: [FilledCall]) -> [FilledFamily] {
		var filledFamilies = [FilledFamily]()
		var indexByFamily = [MockRootParameters.SeamMockBuilder.Family: Int]()
		for filledCall in filledCalls {
			guard let publicMockCall = filledCall.generator.publicMockCall else { continue }
			for (builder, family) in filledCall.filledBuilders {
				guard let receivedProperty = publicMockCall.passedParameters.first(where: { $0.builder?.label == builder.label })?.dependency.property else { continue }
				let callBuilder = MockRootParameters.SeamMockBuilder.FilledCallBuilder(call: ObjectIdentifier(filledCall.generator), label: builder.label)
				let placeProperties = MockRootParameters.SeamMockBuilder.PassedUpBuilder(family: family, calledBuilders: [(builder, publicMockCall.calledBuilders)]).placeProperties
				if let index = indexByFamily[family] {
					filledFamilies[index].callBuilders.append(callBuilder)
					filledFamilies[index].placeProperties += placeProperties
					filledFamilies[index].receivedProperty = min(filledFamilies[index].receivedProperty, receivedProperty)
				} else {
					indexByFamily[family] = filledFamilies.count
					filledFamilies.append(FilledFamily(family: family, callBuilders: [callBuilder], placeProperties: placeProperties, receivedProperty: receivedProperty))
				}
			}
		}
		// A call that re-enters an enclosing call's level function passes what the enclosing call passes, so reads the builder of
		// the enclosing call's family, or of its `@Sendable` twin where the call is made inside a `@Sendable` function.
		for filledCall in filledCalls {
			for reentered in filledCall.reenteredBuilders {
				let enclosingCall = ObjectIdentifier(reentered.enclosingCall)
				guard let enclosingIndex = filledFamilies.firstIndex(where: { $0.callBuilders.contains { $0.call == enclosingCall && $0.label == reentered.enclosingLabel } }) else { continue }
				let callBuilder = MockRootParameters.SeamMockBuilder.FilledCallBuilder(call: ObjectIdentifier(filledCall.generator), label: reentered.label)
				let enclosingFamily = filledFamilies[enclosingIndex].family
				let family = MockRootParameters.SeamMockBuilder.Family(holeType: enclosingFamily.holeType, isSendable: enclosingFamily.isSendable || filledCall.isInsideSendableFunction)
				if let index = indexByFamily[family] {
					filledFamilies[index].callBuilders.append(callBuilder)
				} else {
					indexByFamily[family] = filledFamilies.count
					filledFamilies.append(FilledFamily(family: family, callBuilders: [callBuilder], placeProperties: filledFamilies[enclosingIndex].placeProperties, receivedProperty: filledFamilies[enclosingIndex].receivedProperty))
				}
			}
		}
		return filledFamilies.sorted { ($0.receivedProperty, $0.family.isSendable ? 1 : 0) < ($1.receivedProperty, $1.family.isSendable ? 1 : 0) }
	}

	/// The stems of the hole types of the builders `mock()` takes optional, each with the property a call would receive its
	/// builder as, in sorted order: from one pass over every hole type of the mock's builders, in the order a lifted gate's
	/// mock would read them (its own and its fills' places, then what its calls pass up in the sorted order of the properties
	/// they are received as), unless that pass would rename one of `requiredStems`, those of the builders the mock takes
	/// required, which then keep theirs while the optional builders' hole types take stems from a pass over themselves
	/// alone.
	static func stemsOfOptionalBuilders(
		of optionalHoleTypes: [(holeType: SeamSignature.HoleType, receivedProperty: Property)],
		besideOwnHoleTypes ownHoleTypes: [SeamSignature.HoleType],
		passedUpHoleTypes: [(holeType: SeamSignature.HoleType, receivedProperty: Property)],
		requiredStems: [SeamSignature.HoleType: String],
	) -> [SeamSignature.HoleType: String] {
		guard !optionalHoleTypes.isEmpty else { return [:] }
		var unionHoleTypes = [SeamSignature.HoleType]()
		for holeType in ownHoleTypes + (passedUpHoleTypes + optionalHoleTypes).sorted(by: { $0.receivedProperty < $1.receivedProperty }).map(\.holeType) where !unionHoleTypes.contains(holeType) {
			unionHoleTypes.append(holeType)
		}
		let unionStems = DependencyTreeGenerator.stems(of: unionHoleTypes)
		if requiredStems.allSatisfy({ unionStems[$0.key] == $0.value }) {
			return unionStems
		} else {
			var optionalOnly = [SeamSignature.HoleType]()
			for (holeType, _) in optionalHoleTypes where !optionalOnly.contains(holeType) {
				optionalOnly.append(holeType)
			}
			return DependencyTreeGenerator.stems(of: optionalOnly)
		}
	}

	// MARK: Mock scope context

	// MARK: MockConstruction

	/// How a mock builds one type: the initializer or hand-written mock it calls and the values worked out from it,
	/// which do not depend on the property a node builds. Every node of a type built the same way within one mock root's
	/// tree shares one (`MockConstructions`), so a tree with a node per path holds these once per type, not once per
	/// node.
	final class MockConstruction: Sendable {
		/// The declaration the construction was worked out from, which a node that shares it must equal.
		let instantiable: Instantiable
		/// Whether a compatible user-defined mock method exists for this type.
		let useMockInitializer: Bool
		/// `PublicMockCall.typesDeclaredEscaping` of the node's call, which `builderParameterTypes` reads.
		let builderTypesDeclaredEscaping: Set<TypeDescription>
		let isExtensionBased: Bool
		let defaultParameters: [DefaultParameter]
		let constructionAttributes: String?
		let dependencies: [Dependency]
		let constructionReturnType: TypeDescription
		let customMockName: String?
		let concreteType: TypeDescription
		let sourceFilePath: String?
		let mockDeclarationLocation: Dependency.DeclarationLocation?
		let forwardedProperties: Set<Property>
		/// The labels of `dependencies`.
		let dependencyInnerLabels: Set<String>
		/// Construction arguments surfaced at the mock call site, with elided non-dependency defaults removed (`Self.isElidedInCallSite`).
		let callSiteArguments: [Initializer.Argument]
		/// The parameter types of the builder closures that override how a node is built, one per call-site argument.
		let builderParameterTypes: [TypeDescription]

		init(
			instantiable: Instantiable,
			useMockInitializer: Bool,
			builderTypesDeclaredEscaping: Set<TypeDescription>,
		) {
			self.instantiable = instantiable
			self.useMockInitializer = useMockInitializer
			self.builderTypesDeclaredEscaping = builderTypesDeclaredEscaping
			let constructionInitializer: Initializer? = if useMockInitializer, let mockInitializer = instantiable.mockInitializer {
				mockInitializer
			} else {
				instantiable.initializer
			}
			let constructionArguments = constructionInitializer?.arguments ?? []
			defaultParameters = constructionInitializer.map { constructionInitializer in
				DefaultParameter.defaultParameters(
					of: constructionInitializer,
					dependencies: instantiable.dependencies,
				)
			} ?? []
			constructionAttributes = constructionInitializer?.spelledAttributes
			isExtensionBased = instantiable.declarationType.isExtension
			dependencies = instantiable.dependencies
			constructionReturnType = (useMockInitializer ? instantiable.mockCallReturnType : nil) ?? instantiable.concreteInstantiable
			customMockName = instantiable.customMockName
			concreteType = instantiable.concreteInstantiable
			sourceFilePath = instantiable.sourceFilePath
			mockDeclarationLocation = instantiable.mockDeclarationLocation
			// Collect forwarded properties for Instantiator edges.
			forwardedProperties = Set(
				instantiable.dependencies
					.filter { $0.source == .forwarded }
					.map(\.property),
			)
			let dependencyInnerLabels = Set(instantiable.dependencies.map(\.property.label))
			self.dependencyInnerLabels = dependencyInnerLabels
			let callSiteArguments = constructionArguments.filter { argument in
				!ScopeGenerator.isElidedInCallSite(argument, dependencyInnerLabels: dependencyInnerLabels)
			}
			self.callSiteArguments = callSiteArguments
			// The override closure of a call of another module's public mock passes what it is handed on to that `mock()`, so
			// a function spelled as a name, such as an erased instantiator's `Builder`, is handed `@escaping` where the called
			// mock takes it so (`PublicMockCall.typesDeclaredEscaping`).
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
		}
	}

	/// The constructions one mock root's tree has worked out so far, by concrete type and whether the hand-written mock
	/// builds it, so that a node shares the construction of an earlier node of its type built the same way. A value,
	/// handed down the tree's walk and back, so no task shares it.
	struct MockConstructions: Sendable {
		private struct Key: Hashable {
			let concreteType: TypeDescription
			let useMockInitializer: Bool
		}

		private var constructionsByKey = [Key: [MockConstruction]]()

		/// The construction of `instantiable` built as `useMockInitializer` says, an earlier one where the declaration and
		/// the call's escaping types are equal to its, else a new one, which later nodes share.
		mutating func construction(
			of instantiable: Instantiable,
			useMockInitializer: Bool,
			builderTypesDeclaredEscaping: Set<TypeDescription>,
		) -> MockConstruction {
			let key = Key(concreteType: instantiable.concreteInstantiable, useMockInitializer: useMockInitializer)
			for construction in constructionsByKey[key, default: []] where construction.builderTypesDeclaredEscaping == builderTypesDeclaredEscaping && construction.instantiable == instantiable {
				return construction
			}
			let construction = MockConstruction(
				instantiable: instantiable,
				useMockInitializer: useMockInitializer,
				builderTypesDeclaredEscaping: builderTypesDeclaredEscaping,
			)
			constructionsByKey[key, default: []].append(construction)
			return construction
		}
	}

	// MARK: Mock configuration

	/// The nested configuration struct name (used in struct definitions).
	static let mockConfigurationStructName = "SafeDIMockConfiguration"

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
	fileprivate static func isElidedInCallSite(_ argument: Initializer.Argument, dependencyInnerLabels: Set<String>) -> Bool {
		argument.isLeftToItsDefault
			&& !dependencyInnerLabels.contains(argument.innerLabel)
	}

	/// A payload bound before a mock node's builder function, inside the builder function of the node above
	/// (`valuesBindingsBeforeBuilderFunction`).
	struct MockValuesBinding: Sendable {
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

	/// A directed edge in the global type-reference graph that, when removed,
	/// breaks a cycle. Computed once globally (one back-edge per strongly-connected
	/// component of size > 1) and applied uniformly when generating every type's
	/// configuration struct.
	struct CycleEdge: Hashable {
		let parent: String
		let child: String
	}

	/// A concrete type, and whether it is built with its hand-written mock.
	struct ConstructedType: Hashable {
		let concreteType: TypeDescription
		let usesMockInitializer: Bool
	}

	/// Concrete type names referenced by this scope's mock tree from a
	/// `SendableInstantiator` scope: the walk the fold over the mock root's world (`TypeFactsSendableConfigurations`),
	/// which mock generation reads, is compared with where a test sets
	/// `TypeFactsSendableConfigurationsObservation.comparesWalk`. The tool never runs it.
	///
	/// Read from the generator tree: a node is the lowering's for each child built for a property, inside a `Sendable`
	/// scope where it or an ancestor builds in a `@Sendable` function, and needs a configuration struct where a child of
	/// its own is built for a property, its construction has default-valued parameters, or it closes a cycle.
	nonisolated func sendableConfigurationTypeNames(ofMockRootOf mockedInstantiable: Instantiable) -> Set<String> {
		var result = Set<String>()
		var constructions = MockConstructions()
		// A worklist rather than recursion, since the tree can be as deep as the module has types.
		// Whether a generator's children build what an actor's initializer is handed, outside every lazy wrapper's builder
		// function: such a child reads its overrides as a `@Sendable` builder function does (`isInsideActorArgument`
		// in `MockLowering+Walk.swift`). A mock root that is an actor takes its level so, in an internal mock and a public one
		// alike.
		var generatorsToVisit = [(generator: self, insideSendableScope: false, insideActorArgument: mockedInstantiable.declarationType == .actorType)]
		while let (generator, insideSendableScope, insideActorArgument) = generatorsToVisit.popLast() {
			for child in generator.propertiesToGenerate {
				if case let .property(childInstantiable, childProperty, _, _, isPropertyCycle, _) = child.scopeData {
					let isWrapped = !childProperty.propertyType.isConstant
					let childInsideSendableScope = insideSendableScope || child.buildsInSendableFunction || insideActorArgument
					if childInsideSendableScope {
						let needsConfigurationStruct = isPropertyCycle
							|| child.propertiesToGenerate.contains(where: \.isBuiltForProperty)
							|| !constructions.construction(
								of: childInstantiable,
								useMockInitializer: childInstantiable.mockReturnTypeIsCompatible(withPropertyType: childProperty.typeDescription.asInstantiatedType),
								builderTypesDeclaredEscaping: child.publicMockCall?.typesDeclaredEscaping ?? [],
							).defaultParameters.isEmpty
						if needsConfigurationStruct {
							result.insert(childInstantiable.concreteInstantiable.asSource)
						}
					}
					let usesMockInitializer = childInstantiable.mockReturnTypeIsCompatible(withPropertyType: childProperty.typeDescription.asInstantiatedType)
					let childInsideActorArgument = (childInstantiable.declarationType == .actorType && !usesMockInitializer) || (insideActorArgument && !isWrapped)
					generatorsToVisit.append((generator: child, insideSendableScope: childInsideSendableScope, insideActorArgument: childInsideActorArgument))
				}
			}
		}
		return result
	}

	/// Whether this scope is built for a property, which the mock's lowering makes a property node of.
	nonisolated private var isBuiltForProperty: Bool {
		if case .property = scopeData {
			true
		} else {
			false
		}
	}

	/// The builder `mock()` takes for each place of a public mock of another module that a fill of one of `calls` builds
	/// inline, as `holeBuildersByInlinePlace(in:buildersByFamily:foreignPublicMocks:)` finds them outside every fill, keyed
	/// by the place's scope generator, which the fill's code reads (`propertyCode`). A call inside a fill is one of `calls`
	/// itself, so each fill's tree is walked down to the calls it makes.
	static func holeBuildersByInlinePlaceInFills(
		of calls: [FilledCall],
		buildersByFamily: [MockRootParameters.SeamMockBuilder.Family: FillPlaceBindings.HoleBuilder],
		foreignPublicMocks: [TypeDescription: SeamResolution.ForeignPublicMock],
	) throws -> [ObjectIdentifier: FillPlaceBindings.HoleBuilder] {
		guard !buildersByFamily.isEmpty, !foreignPublicMocks.isEmpty else { return [:] }
		var holeBuilders = [ObjectIdentifier: FillPlaceBindings.HoleBuilder]()
		var declaringModulesSight = DeclaringModulesSight()
		// Each scope with whether it is built inside a `@Sendable` function, the public mock built inline nearest above it,
		// and the type its declaration instantiates, which a `fulfilledByType:` names.
		var generatorsToVisit = [(generator: ScopeGenerator, isInsideSendableFunction: Bool, publicMockBuiltInline: SeamResolution.ForeignPublicMock?, instantiatedType: TypeDescription?)]()
		for call in calls {
			for fill in call.generator.propertiesToGenerate where fill.fillHole != nil && fill.fillEmitsCode {
				let fillIsInsideSendableFunction = call.isInsideSendableFunction || call.generator.buildsInSendableFunction(ofFill: fill)
				generatorsToVisit += fill.propertiesToGenerate.map { ($0, fillIsInsideSendableFunction, nil, nil) }
			}
		}
		while let (generator, isInsideSendableFunction, publicMockBuiltInline, declaredInstantiatedType) = generatorsToVisit.popLast() {
			// A scope that closes a cycle builds nothing, and a call's places are the call's.
			guard case let .property(instantiable, property, _, _, false, _) = generator.scopeData, generator.publicMockCall == nil else { continue }
			let instantiatedType = declaredInstantiatedType ?? property.typeDescription.asInstantiatedType
			if let publicMockBuiltInline,
			   try !declaringModulesSight.sees(instantiatedType, declaredBesides: publicMockBuiltInline)
			{
				let family = MockRootParameters.SeamMockBuilder.Family(
					holeType: SeamSignature.HoleType(instantiatedType: instantiatedType.spelledCanonically, builtType: property.typeDescription.builtTypeOfWrapper.spelledCanonically),
					isSendable: isInsideSendableFunction || property.propertyType.isSendable,
				)
				holeBuilders[ObjectIdentifier(generator)] = buildersByFamily[family]
			}
			let enclosingPublicMock = foreignPublicMocks[instantiable.concreteInstantiable] ?? publicMockBuiltInline
			let instantiatedTypes = Dictionary(instantiable.dependencies.map { ($0.property, $0.asInstantiatedType) }, uniquingKeysWith: { first, _ in first })
			let childIsInsideSendableFunction = isInsideSendableFunction || generator.buildsInSendableFunction
			generatorsToVisit += generator.propertiesToGenerate.map { child in
				(child, childIsInsideSendableFunction, enclosingPublicMock, child.property.flatMap { instantiatedTypes[$0] })
			}
		}
		return holeBuilders
	}

	/// What the module that declares a public mock built inline sees, resolved once per module and only for a module whose
	/// public mock a tree builds inline (`SeamResolution.ForeignPublicMock.visibleDeclarations`), which the walks of the
	/// places built inline inside and outside fills both read.
	struct DeclaringModulesSight {
		/// Whether the module that declares `publicMock` sees an instantiable of `type`: a type it sees is not a hole of it.
		mutating func sees(_ type: TypeDescription, declaredBesides publicMock: SeamResolution.ForeignPublicMock) throws -> Bool {
			if let instantiables = instantiablesByModule[publicMock.declaringModule] {
				return instantiables[type] != nil
			} else {
				let instantiables = try publicMock.visibleDeclarations().instantiables
				instantiablesByModule[publicMock.declaringModule] = instantiables
				return instantiables[type] != nil
			}
		}

		private var instantiablesByModule = [ModuleIdentity: [TypeDescription: Instantiable]]()
	}

	/// The `@Instantiated` dependencies of a mock's types that the mock cannot build, which `mock()` takes as
	/// parameters, one for each label and type, in the order they are found.
	private struct UncoveredDependencies {
		private(set) var properties = [Property]()
		/// The type each parameter is spelled with.
		private(set) var typeSources = [String]()
		/// The type each dependency instantiates, which no `@Instantiable` declaration fulfills.
		private(set) var instantiatedTypes = [TypeDescription]()
		/// Each dependency.
		private(set) var dependencies = [Dependency]()
		/// The indices of the dependencies whose label a builder function around a type passed them declares.
		private(set) var indicesHiddenWhereReferenced = Set<Int>()
		/// The indices of the dependencies that a type built inside a `@Sendable` builder function instantiates
		/// (`MockRootParameters.UncoveredParameter.isSendableAutoclosure`).
		private(set) var indicesInstantiatedInSendableFunction = Set<Int>()

		/// Adds a dependency the lowering's walk lists once, having merged every type that creates it
		/// (`MockTreeNames.uncoveredDependencies`), so no dependency is added twice.
		mutating func add(_ dependency: Dependency, isHiddenWhereReferenced: Bool, isInstantiatedInSendableFunction: Bool) {
			let property = dependency.property
			let index = properties.count
			properties.append(property)
			// Route through `asFunctionParameter` so closure types surface
			// as `@escaping` — matching the `rootDefaultParameters` and
			// flat-received emission conventions. Idempotent for non-closures.
			typeSources.append(property.propertyType.isConstant
				? property.typeDescription.asInstantiatedTypeSpelledAsDeclared.asFunctionParameter.asSource
				: property.typeDescription.asFunctionParameter.asSource)
			instantiatedTypes.append(dependency.asInstantiatedType)
			dependencies.append(dependency)
			if isHiddenWhereReferenced {
				indicesHiddenWhereReferenced.insert(index)
			}
			if isInstantiatedInSendableFunction {
				indicesInstantiatedInSendableFunction.insert(index)
			}
		}
	}

	// MARK: Mock Parameter Naming

	/// Computes disambiguated property labels for the properties of a list of nodes at the same scope level.
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
		forProperties nodes: [Property],
		besideParametersKeepingTheirLabels parametersKeepingTheirLabels: [Property] = [],
		reservedNames: Set<String> = [],
	) -> [String: [TypeDescription: String]] {
		let labels = nodes.map(\.label)
		let parameterLabels = Set(parametersKeepingTheirLabels.map(\.label))
		let collidingLabels = collidingLabels(in: labels).union(parameterLabels.intersection(labels))
		let collidingNodes = nodes.filter { collidingLabels.contains($0.label) }
		let collidingNames = identifierSafeNames(
			for: collidingNodes.map {
				let instantiatedTypeDescription = $0.typeDescription.asInstantiatedType
				return (
					label: $0.label,
					suffixTypes: [instantiatedTypeDescription.simplified, instantiatedTypeDescription, $0.typeDescription],
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
		for node in nodes where !collidingLabels.contains(node.label) {
			result[node.label, default: [:]][node.typeDescription] = node.label
		}
		for (node, name) in zip(collidingNodes, collidingNames) {
			result[node.label, default: [:]][node.typeDescription] = name
		}
		return result
	}

	/// The names `properties`, the property children of one scope whose labels are `labels`, are bound to:
	/// each property’s label, disambiguated as `labelMap`, from `disambiguatePropertyLabels`, names it when
	/// siblings or a parameter that keeps its label share it.
	static func bindingNames(
		of properties: [Property],
		labels: Set<String>,
		labelMap: [String: [TypeDescription: String]],
	) -> Set<String> {
		guard labels.count < properties.count
			|| labelMap.contains(where: { label, namesByTypeDescription in namesByTypeDescription.values.contains { $0 != label } })
		else { return labels }
		return Set(properties.map { labelMap[$0.label]?[$0.typeDescription] ?? $0.label })
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
	// D1 lane hook (lane D): the lowering names the overrides and parameters of `mock()` apart as the emitter does.
	static func onlyIfAvailableOverrides(
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
	// D1 lane hook (lane D): the lowering names the parameters of `mock()` apart as the emitter does.
	static func namesApart(
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
		for property: Property,
		labelMap: [String: [TypeDescription: String]],
	) -> String {
		// safedi-source-rule: allow forceUnwrap — every caller passes the `labelMap` that `disambiguatePropertyLabels` made of properties that include `property`, and it names each of them.
		labelMap[property.label]![property.typeDescription]!
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

	// MARK: Mock Override Reads

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
	///
	/// Where the function builds a node whose configuration is `Sendable` (`configurationPath`), the function reads the
	/// whole configuration from one local instead, `<function>__overrides`, and every read beneath it is that local's
	/// member: a configuration of the `Sendable` form whose every field is proven `Sendable` is itself `Sendable`
	/// (`ConfigurationRecord.configurationStruct`), and it holds its fields behind one immutable reference, so the read
	/// gives each field the value the read of the field would.
	final class SendableOverrideExtractor {
		/// - Parameter configurationPath: The path of the configuration of the node whose builder function starts the
		///   extraction, where that configuration is `Sendable`, which the function then reads through one local.
		init(functionName: String, names: GeneratedNameAllocator, configurationPath: String? = nil) {
			self.functionName = functionName
			self.names = names
			self.configurationPath = configurationPath
		}

		/// Records that `expression` is read into a local named after the
		/// outermost `@Sendable` function, and returns that local's name, or the member of the configuration's local
		/// that `expression` reads. An expression read before, as the override path of a type a cycle builds again is
		/// the path of the nearest same-type place above it, returns the local that read it, so one override is read
		/// into one local.
		func extract(_ expression: String, localNameSuffix: String) -> String {
			if let configurationPath, expression.hasPrefix("\(configurationPath).") {
				let localName: String
				if let configurationLocalName {
					localName = configurationLocalName
				} else {
					localName = names.claim("\(functionName)__\(Self.configurationLocalNameSuffix)".spelledAsJoinedIdentifier)
					configurationLocalName = localName
					extractions.append((localName: localName, expression: configurationPath))
				}
				return localName + expression.dropFirst(configurationPath.count)
			} else if let localName = localNameByExpression[expression] {
				return localName
			} else {
				let localName = names.claim("\(functionName)__\(localNameSuffix)".spelledAsJoinedIdentifier)
				extractions.append((localName: localName, expression: expression))
				localNameByExpression[expression] = localName
				return localName
			}
		}

		/// The local each expression extracted so far was read into.
		private var localNameByExpression = [String: String]()

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
		private let configurationPath: String?
		/// The local the configuration at `configurationPath` is read into, once something reads it.
		private var configurationLocalName: String?

		/// The suffix of the name of the local a whole configuration is read into.
		private static let configurationLocalNameSuffix = "overrides"
	}
}

// MARK: - DefaultParameter

extension ScopeGenerator {
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

// MARK: - Instantiable

extension Instantiable {
	// D1 lane hook (lane D): the mock lowering spells the comment too.
	static let incorrectlyConfiguredComment = "/* @Instantiable type is incorrectly configured. Fix errors from @Instantiable macro to fix this error. */"

	fileprivate func generateArgumentList(
		unavailableProperties: Set<Property>? = nil,
		lazilyInstantiatedInstanceProperties: Set<Property> = [],
	) throws -> String {
		try initializer?
			.createInitializerArgumentList(
				given: dependencies,
				unavailableProperties: unavailableProperties,
				lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties,
			) ?? Self.incorrectlyConfiguredComment
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
		callGuard(for: concreteType).spelled
	}

	/// The guard line's record, of a call of `concreteType`.
	func callGuard(for concreteType: TypeDescription) -> CallGuard {
		CallGuard(calledType: concreteType, guardTypeName: guardTypeName, comment: comment)
	}
}

extension TypeDescription {
	/// This type, or, for a throwing `@autoclosure`, the `@autoclosure` that does not throw and returns the same value: how a
	/// mock takes a default-valued `@autoclosure` it calls where it builds the type (`Initializer.Argument.isLeftToItsDefault`).
	// D1 lane hook (lane D): the mock lowering takes the parameter so too.
	var autoclosureTakenWithoutThrowing: TypeDescription {
		guard case let .attributed(.closure(arguments, isAsync, true, _, returnType), specifiers, attributes) = self,
		      // safedi-source-rule: allow stringScan — `attributes` is a type’s `[String]` of attributes: membership among a few elements, no scan of text.
		      attributes.contains("autoclosure")
		else { return self }
		return .attributed(.closure(arguments: arguments, isAsync: isAsync, doesThrow: false, thrownType: nil, returnType: returnType), specifiers: specifiers, attributes: attributes)
	}
}

extension ScopeGenerator: CycleParameterSearchNode {
	nonisolated var searchProperty: Property? {
		property
	}

	nonisolated var searchReceivedProperties: Set<Property> {
		receivedProperties
	}

	nonisolated var searchRequiredReceivedProperties: Set<Property> {
		requiredReceivedProperties
	}

	nonisolated var searchRequiredAliasFulfillingProperties: Set<Property> {
		requiredAliasFulfillingProperties
	}

	nonisolated var searchOnlyIfAvailableAliasFulfillingProperty: Property? {
		onlyIfAvailableAliasFulfillingProperty
	}

	nonisolated var searchOnlyIfAvailableUnwrappedReceivedProperties: Set<Property> {
		onlyIfAvailableUnwrappedReceivedProperties
	}

	nonisolated var searchUnpassableCycleLabelsInTree: [UnpassableCycleLabel] {
		unpassableCycleLabelsInTree
	}

	nonisolated var searchBuiltInstantiable: Instantiable? {
		builtInstantiable
	}

	nonisolated var searchCycleParameters: [CycleParameter] {
		cycleParameters
	}

	nonisolated var searchClosesPropertyCycle: Bool {
		closesPropertyCycle
	}

	nonisolated var searchClosedOnDeclaration: BuiltDeclaration? {
		closedOnDeclaration
	}

	nonisolated var searchChildren: [ScopeGenerator] {
		propertiesToGenerate
	}

	nonisolated var searchIdentity: ObjectIdentifier {
		ObjectIdentifier(self)
	}

	/// Whether a child's subtree closes a cycle on a scope enclosing the child, or a child is the scope a cycle beneath it
	/// closes on (see `childrenTakePartInCycle`).
	nonisolated var searchChildrenTakePartInCycle: Bool {
		childrenTakePartInCycle
	}
}
