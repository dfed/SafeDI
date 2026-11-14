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
	///   - closedOnDeclaration: For a scope that closes a property cycle, the declaration it repeats (see
	///     `closedOnDeclaration`).
	init(
		instantiable: Instantiable,
		property: Property?,
		propertiesToGenerate: [ScopeGenerator],
		propertiesToDeclare: Set<Property>,
		unavailableOptionalProperties: Set<Property>,
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
		passedUpHoles: [SeamSignature.Hole] = [],
		valuesBindings: [SeamHoles.ValuesBinding] = [],
		isBuiltByFill: Bool = false,
		fill: (hole: SeamSignature.Hole, key: String, functionName: String, boundLabels: Set<String>, fields: [SeamSignature.Hole.Field], caseHoles: [SeamSignature.Hole], emitsCode: Bool, callerReads: FillCallerReads)? = nil,
		constructsWithHandWrittenMock: Bool = false,
		cycleParameters: [CycleParameter] = [],
		builtCycleParameters: [CycleParameter] = [],
		cycleParameterUnavailableProperties: Set<Property> = [],
		callSiteLazilyInstantiatedInstanceProperties: Set<Property>? = nil,
		reboundProperties: Set<Property> = [],
		previousPassReceivedBuilderLoops: ReceivedBuilderLoops? = nil,
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
		fillFields = fill?.fields ?? []
		fillCaseHoles = fill?.caseHoles ?? []
		fillEmitsCode = fill?.emitsCode ?? true
		fillCallerReads = fill?.callerReads ?? FillCallerReads()
		ownerPropertyStack = []
		ownerConcreteTypeStack = []
		self.passedUpHoles = passedUpHoles
		self.valuesBindings = valuesBindings
		self.isBuiltByFill = isBuiltByFill
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
		// This runs at every scope of every tree, and nearly every child is outside every cycle.
		var childCycleClosedOnDeclarations = Set<BuiltDeclaration>()
		var childrenTakePartInCycle = false
		for child in propertiesToGenerate where child.isReferencedByCycleClosingScope || !child.cycleClosedOnDeclarations.isEmpty {
			childCycleClosedOnDeclarations.formUnion(child.cycleClosedOnDeclarations)
			childrenTakePartInCycle = true
		}
		self.childrenTakePartInCycle = childrenTakePartInCycle
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
		for child in propertiesToGenerate where !child.typesDeclaredEscaping.isEmpty {
			typesDeclaredEscaping.formUnion(child.typesDeclaredEscaping)
		}
		self.typesDeclaredEscaping = typesDeclaredEscaping
		declaresBuilderFunction = property != nil && !isPropertyCycle
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
		for child in propertiesToGenerate {
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
		self.buildsInSendableFunction = buildsInSendableFunction
		self.cycleClosedOnDeclarationsReferencedFromSendableFunction = cycleClosedOnDeclarationsReferencedFromSendableFunction
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
			if let enclosingFillKey = builderCallArgument.enclosingFillKey {
				referencedFillNamesByKey[enclosingFillKey] = builderCallArgument.value
				if builderCallArgument.isSendable {
					fillKeysReferencedFromSendableFunction.insert(enclosingFillKey)
				}
			}
		}
		for child in propertiesToGenerate where !child.referencedFillNamesByKey.isEmpty {
			referencedFillNamesByKey.merge(child.referencedFillNamesByKey) { name, _ in name }
			fillKeysReferencedFromSendableFunction.formUnion(child.fillKeysReferencedFromSendableFunction)
		}
		let ownFills = propertiesToGenerate.compactMap { child -> SendableFillNode? in
			child.fillKey.map { SendableFillNode(key: $0, references: Set(child.referencedFillNamesByKey.keys), startsSendable: child.fillHole?.isSendable == true) }
		} + fillDispatchers.map { dispatcher in
			SendableFillNode(key: dispatcher.key, references: Set(dispatcher.cases.compactMap(\.target?.key)), startsSendable: dispatcher.isSendableFamily)
		}
		// A call's own fills and dispatchers are declared in the function that makes it, which encloses every reference to them.
		let ownFillKeys = Set(ownFills.map(\.key))
		if buildsInSendableFunction {
			fillKeysReferencedFromSendableFunction.formUnion(referencedFillNamesByKey.keys.filter { !ownFillKeys.contains($0) })
		}
		let sendableFills = Self.sendableFills(of: ownFills, referencedFromSendableFunctions: fillKeysReferencedFromSendableFunction)
		sendableFillKeys = sendableFills.keys
		fillKeysReferencedFromSendableFunction.formUnion(sendableFills.referencedFillKeys)
		// A fill that one case of one of the call's dispatchers calls, and nothing else refers to by name, is generated in
		// that case: one function fewer for each place, which is most of what a caller compiles. What refers to a fill by
		// name is a call's argument (an enclosing fill or dispatcher a call inside it passes) and a
		// dispatcher's case, the call's own or a call's inside one of its fills.
		var childNamedFillKeys = Set<String>()
		for child in propertiesToGenerate where !child.namedFillKeys.isEmpty {
			childNamedFillKeys.formUnion(child.namedFillKeys)
		}
		var namedFillKeys = childNamedFillKeys
		for enclosingFillKey in builderCallArguments.compactMap(\.enclosingFillKey) {
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
		self.namedFillKeys = namedFillKeys.subtracting(ownFillKeys)
		let sendableFillKeys = sendableFillKeys
		inlinableFillKeys = Set(propertiesToGenerate.compactMap { child -> String? in
			guard let key = child.fillKey,
			      dispatcherCaseCountByTargetKey[key] == 1,
			      !childNamedFillKeys.contains(key),
			      let dispatcher = dispatcherByTargetKey[key],
			      // A dispatcher that takes `passUp` keeps calling its fills: its parameter would hide a `passUp` the fill reads
			      // from the caller's scope.
			      !dispatcher.takesPassUp,
			      // A `@Sendable` dispatcher holds only a `@Sendable` fill's body, and a fill other than `@Sendable` only in a
			      // dispatcher that is not.
			      sendableFillKeys.contains(key) == sendableFillKeys.contains(dispatcher.key)
			else { return nil }
			return key
		})
		// A call's fills whose hole has a field bound from a deferred parameter read it from the caller's scope, unless a
		// call inside one of them passes it on beneath another declaration of the label. Nearly no scope calls such a seam.
		let fillsWithDeferredFields = propertiesToGenerate.compactMap { fill -> (fill: ScopeGenerator, key: String)? in
			// A fill of a case nested by type binds a level's field where a route holds one, whatever another route's deferred one.
			guard let key = fill.fillKey, fill.fillFields.contains(where: \.isDeferredParameter) else { return nil }
			return (fill, key)
		}
		var fillDeferredLabelsHiddenByReenteringCalls = [String: Set<String>]()
		var fillStructBoundLabelsChangedInTree = propertiesToGenerate.contains(where: \.fillStructBoundLabelsChangedInTree)
		if !fillsWithDeferredFields.isEmpty {
			let hiddenByFillKey = DependencyTreeGenerator.hiddenByReenteringCalls(ofFills: propertiesToGenerate)
			for (fill, key) in fillsWithDeferredFields {
				let deferredLabels = Set(fill.fillFields.filter(\.isDeferredParameter).map(\.property.label))
				let hiddenLabels = deferredLabels.intersection(hiddenByFillKey[key].map { Set($0.pathDeclarations.keys) } ?? [])
				if !hiddenLabels.isEmpty {
					fillDeferredLabelsHiddenByReenteringCalls[key] = hiddenLabels
				}
				if fill.fillStructBoundLabels.intersection(deferredLabels) != hiddenLabels {
					fillStructBoundLabelsChangedInTree = true
				}
			}
		}
		self.fillDeferredLabelsHiddenByReenteringCalls = fillDeferredLabelsHiddenByReenteringCalls
		self.fillStructBoundLabelsChangedInTree = fillStructBoundLabelsChangedInTree
		self.referencedFillNamesByKey = referencedFillNamesByKey.filter { !ownFillKeys.contains($0.key) }
		self.fillKeysReferencedFromSendableFunction = fillKeysReferencedFromSendableFunction.subtracting(ownFillKeys)
		self.propertiesToDeclare = propertiesToDeclare
		self.unavailableOptionalProperties = unavailableOptionalProperties
		self.lazilyInstantiatedInstanceProperties = lazilyInstantiatedInstanceProperties
		fulfillingPropertyIsLazilyInstantiatedInstance = false
		fulfillingBindingIsOptional = false
		fulfillingExpression = nil
		declaredLazilyInstantiatedInstanceProperty = property?.asLazilyInstantiatedInstanceProperty
		onlyIfAvailableDependencies = instantiable.dependencies.compactMap { dependency in
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
		/// Whether this scope declares or forwards a form of `property` that a receive of it only if available reads (see
		/// `Property.formsReadByOnlyIfAvailableReceive`): the receive reads that nearest declaration, and receives nothing
		/// from this scope's ancestors.
		func providesAFormReadByOnlyIfAvailableReceive(of property: Property) -> Bool {
			property.formsReadByOnlyIfAvailableReceive.contains { propertiesToDeclare.contains($0) || forwardedProperties.contains($0) }
		}
		// All the properties our children require be passed in, unioned with the properties we
		// require to fulfill our own dependencies, and those of them some receiver requires. A
		// child's required properties are among its received ones, so each child's received
		// properties are read once, with no intermediate sets: this runs at every scope of every tree.
		var receivedProperties = Set<Property>()
		var requiredReceivedProperties = Set<Property>()
		for child in propertiesToGenerate {
			for property in child.receivedProperties where isReceivedFromAncestors(property) {
				let isRequired = child.requiredReceivedProperties.contains(property)
				guard isRequired || !providesAFormReadByOnlyIfAvailableReceive(of: property) else { continue }
				receivedProperties.insert(property)
				if isRequired {
					requiredReceivedProperties.insert(property)
				}
			}
		}
		// A scope that closes a cycle builds nothing, but the builder function it calls declares what its type instantiates
		// and forwards, so an alias of one of those is bound inside that function, which binds its own: the scope receives
		// nothing for it.
		let aliasBindingDeclaredProperties = isPropertyCycle ? Self.propertiesDeclared(byOwnDependencies: instantiable.dependencies) : propertiesToDeclare
		// The properties this scope's own dependencies receive.
		var ownReceivedProperties = Set<Property>()
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
				// An `onlyIfAvailable` alias binds a local of any form it reads.
				guard !Self.declaresFulfillingProperty(
					of: fulfillingProperty,
					onlyIfAvailable: isOnlyIfAvailable,
					declaredProperties: aliasBindingDeclaredProperties,
					forwardedProperties: forwardedProperties,
				) else { continue }
				receivedProperty = fulfillingProperty
				onlyIfAvailable = isOnlyIfAvailable
			}
			receivedProperties.insert(receivedProperty)
			ownReceivedProperties.insert(receivedProperty)
			if !onlyIfAvailable {
				requiredReceivedProperties.insert(receivedProperty)
			}
		}
		// A scope that closes a lazy cycle passes the function it refers to what that function's body receives under each
		// parameter's label, so it receives those forms as the body does.
		if isPropertyCycle {
			for parameter in cycleParameters {
				receivedProperties.formUnion(parameter.receivedForms)
				requiredReceivedProperties.formUnion(parameter.requiredForms)
			}
		}
		self.receivedProperties = receivedProperties
		self.requiredReceivedProperties = requiredReceivedProperties
		// The properties only the leaves that call another module's public mock receive: each receives them only if
		// available, and passes them where the tree provides them. Nearly every subtree calls no public mock.
		var receivedOnlyByPublicMockCalls = Set<Property>()
		if publicMockCall != nil {
			for dependency in instantiable.dependencies where dependency.source == .received(onlyIfAvailable: true) {
				receivedOnlyByPublicMockCalls.insert(dependency.property)
			}
		}
		for child in propertiesToGenerate {
			for property in child.receivedOnlyByPublicMockCalls where isReceivedFromAncestors(property) {
				receivedOnlyByPublicMockCalls.insert(property)
			}
		}
		if !receivedOnlyByPublicMockCalls.isEmpty {
			// A property another receiver receives is not only the leaves'.
			for child in propertiesToGenerate {
				receivedOnlyByPublicMockCalls.subtract(child.receivedProperties.subtracting(child.receivedOnlyByPublicMockCalls))
			}
			if publicMockCall == nil {
				receivedOnlyByPublicMockCalls.subtract(ownReceivedProperties)
			}
		}
		self.receivedOnlyByPublicMockCalls = receivedOnlyByPublicMockCalls
		// Of those, the ones some call passes: the tier it reaches takes them. Others are omitted by every call.
		var passedByPublicMockCalls = Set<Property>()
		if !receivedOnlyByPublicMockCalls.isEmpty {
			if let publicMockCall {
				for parameter in publicMockCall.passedParameters where parameter.dependency.source == .received(onlyIfAvailable: true) {
					passedByPublicMockCalls.insert(parameter.dependency.property)
				}
			}
			for child in propertiesToGenerate {
				passedByPublicMockCalls.formUnion(child.passedByPublicMockCalls)
			}
			passedByPublicMockCalls.formIntersection(receivedOnlyByPublicMockCalls)
		}
		self.passedByPublicMockCalls = passedByPublicMockCalls
		var unwrappedOptionalRequiredReceivedProperties = Set<Property>()
		for property in requiredReceivedProperties where property.typeDescription.isOptional {
			unwrappedOptionalRequiredReceivedProperties.insert(property.asUnwrappedProperty)
		}
		self.unwrappedOptionalRequiredReceivedProperties = unwrappedOptionalRequiredReceivedProperties
		// A child's tree requires an `onlyIfAvailable` alias this scope declares when a receiver in it requires the alias's
		// property, or an alias in it that is required is fulfilled by that property. The alias is bound from the nearest
		// declaration of its fulfilling property's label, so that declaration is built first: a sibling here (see
		// `orderedPropertiesToGenerate`), or, where this scope declares none, one an enclosing scope declares, which this
		// scope's `requiredAliasFulfillingProperties` carries up until a scope declares the label. No alias of a scope
		// renames another (SafeDITool rejects that before it validates a tree that builds the scope), so a child's
		// requirement is the only way.
		func isRequiredByChild(_ property: Property) -> Bool {
			propertiesToGenerate.contains { child in
				child.requiredReceivedProperties.contains(property)
					|| child.requiredAliasFulfillingProperties.contains { $0.label == property.label && Self.provides(property, aFormReadBy: $0) }
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
		// A requirement stops at the nearest declaration of its label, whatever form that declaration has: the alias reads
		// it, or is `nil` where it provides no form the alias reads.
		var declaredLabels = Set(forwardedProperties.map(\.label))
		for declaredProperty in propertiesToDeclare {
			declaredLabels.insert(declaredProperty.label)
		}
		// A call of a seam whose tree requires one of its pass-throughs through an `onlyIfAvailable` alias requires it too
		// (`SeamSignature.Parameter.requiredThroughAlias`): the seam's alias is bound from that parameter. Validation reads
		// the same requirement from the seam's tree, which it walks inline, so `collectReceivedProperties` meets no seam call.
		requiredAliasFulfillingProperties = Set(propertiesToGenerate.flatMap(\.requiredAliasFulfillingProperties))
			.union(requiredOnlyIfAvailableAliasFulfillingProperties)
			.union(isPropertyCycle ? cycleParameters.flatMap(\.requiredAliasFulfillingForms) : [])
			.union(seamCall?.requiredThroughAliasProperties ?? [])
			.filter { !declaredLabels.contains($0.label) }
		onlyIfAvailableAliasFulfillingProperty = nil
		var onlyIfAvailableUnwrappedReceivedPropertiesIncludingRequired = Set<Property>()
		for propertyToGenerate in propertiesToGenerate {
			for property in propertyToGenerate.onlyIfAvailableUnwrappedReceivedProperties
				where !providesAFormReadByOnlyIfAvailableReceive(of: property)
			{
				onlyIfAvailableUnwrappedReceivedPropertiesIncludingRequired.insert(property)
			}
		}
		for dependency in instantiable.dependencies {
			switch dependency.source {
			case .instantiated, .forwarded:
				continue
			case let .received(onlyIfAvailable):
				guard onlyIfAvailable else { continue }
				onlyIfAvailableUnwrappedReceivedPropertiesIncludingRequired.insert(dependency.property.asUnwrappedProperty)
			case let .aliased(fulfillingProperty, _, onlyIfAvailable):
				// Skip locally-declared and forwarded fulfilling properties —
				// the alias binds to the local, not to an ancestor.
				guard onlyIfAvailable, !Self.declaresFulfillingProperty(
					of: fulfillingProperty,
					onlyIfAvailable: true,
					declaredProperties: aliasBindingDeclaredProperties,
					forwardedProperties: forwardedProperties,
				) else { continue }
				onlyIfAvailableUnwrappedReceivedPropertiesIncludingRequired.insert(fulfillingProperty.asUnwrappedProperty)
			}
		}
		if isPropertyCycle {
			for parameter in cycleParameters {
				onlyIfAvailableUnwrappedReceivedPropertiesIncludingRequired.formUnion(parameter.onlyIfAvailableUnwrappedForms)
			}
		}
		// A property some receiver requires is required, even where others receive
		// it only if available. Few subtrees receive anything only if available, so the
		// required properties are unwrapped only for those that do.
		onlyIfAvailableUnwrappedReceivedProperties = onlyIfAvailableUnwrappedReceivedPropertiesIncludingRequired.isEmpty
			? onlyIfAvailableUnwrappedReceivedPropertiesIncludingRequired
			: onlyIfAvailableUnwrappedReceivedPropertiesIncludingRequired.subtracting(requiredReceivedProperties.map(\.asUnwrappedProperty))
		// The labels the scopes between each cycle-closing scope in this subtree and the scope it closes on declare, by the
		// declaration the cycle closes on. A scope a cycle closes on takes those of them its tree receives from the scopes
		// enclosing it as parameters of its builder function. Nearly every scope takes part in no cycle.
		var cycleClosingRedeclaredLabels = [BuiltDeclaration: [String: CycleParameter.Redeclaration]]()
		if let closedOnDeclaration {
			cycleClosingRedeclaredLabels[closedOnDeclaration] = [:]
		} else if childrenTakePartInCycle {
			for child in propertiesToGenerate {
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
					firstReceives: Self.inOrderTheBodyFirstReceives(
						ofLabels: receivedRedeclarations,
						builtProperty: property,
						builtDeclaration: declaration,
						builtType: instantiable.concreteInstantiable,
						ownDependencies: instantiable.dependencies,
						children: propertiesToGenerate,
					).map { (label: $0.label, receiver: $0.receiver, redeclaration: $0.value) },
					receivedProperties: receivedProperties,
					requiredReceivedProperties: requiredReceivedProperties,
					requiredAliasFulfillingProperties: requiredAliasFulfillingProperties,
					onlyIfAvailableUnwrappedReceivedProperties: onlyIfAvailableUnwrappedReceivedProperties,
					builtType: instantiable.concreteInstantiable,
				)
			}
		}
		for child in propertiesToGenerate where !child.unpassableCycleLabelsInTree.isEmpty {
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
		self.cycleClosingRedeclaredLabels = cycleClosingRedeclaredLabels
		self.foundCycleParameters = foundCycleParameters
		self.unpassableCycleLabelsInTree = unpassableCycleLabelsInTree
		cycleParametersChangedInTree = foundCycleParameters != builtCycleParameters
			|| propertiesToGenerate.contains(where: \.cycleParametersChangedInTree)
		// A scope that closes a cycle builds nothing, so its children are on no loop. A fill's one child is the property it
		// fills, whose builder function the seam's initializer declares: a receive of that property in the fill's tree is a
		// fill finding (`receivesInstantiatorBuildingSite`), never a loop the fill rebinds.
		let receivedBuilderLoops = isPropertyCycle || fill != nil
			? ReceivedBuilderLoops()
			: Self.receivedBuilderLoops(of: propertiesToGenerate, requiredOnlyIfAvailableAliasProperties: requiredOnlyIfAvailableAliasProperties)
		self.receivedBuilderLoops = receivedBuilderLoops
		receivedBuilderLoopsChangedInTree = receivedBuilderLoops != (previousPassReceivedBuilderLoops ?? ReceivedBuilderLoops())
			|| propertiesToGenerate.contains(where: \.receivedBuilderLoopsChangedInTree)
		// The function rebinds what its tree receives inside its loop, in the order its body first receives each, except a
		// label its own parameters name: the body reads the parameter.
		if let property, let declaration, !isPropertyCycle, !reboundProperties.isEmpty {
			var parameterLabels = Set(forwardedProperties.map(\.label))
			for parameter in cycleParameters {
				parameterLabels.insert(parameter.property.label)
			}
			// The forms of each label, in property order: a mock root can promote a label in two forms, both on one loop.
			var reboundFormsByLabel = [String: [Property]]()
			for reboundProperty in reboundProperties.sorted() where !parameterLabels.contains(reboundProperty.label) {
				reboundFormsByLabel[reboundProperty.label, default: []].append(reboundProperty)
			}
			// Of a label promoted in two forms, the function rebinds each form its body reads – the form a receive names, or
			// the non-optional one where a required optional receive has no form of its own – and none it does not read, which
			// would be an unused binding. Each label is decided on its own, so the order of the dictionary reaches nothing.
			for (label, forms) in reboundFormsByLabel where forms.count > 1 {
				let readForms = forms.filter { form in
					receivedProperties.contains(form)
						|| (!form.typeDescription.isOptional && receivedProperties.contains(form.asOptionalProperty) && !forms.contains(form.asOptionalProperty))
				}
				reboundFormsByLabel[label] = readForms.isEmpty ? nil : readForms
			}
			let firstReceives = Self.inOrderTheBodyFirstReceives(
				ofLabels: reboundFormsByLabel,
				builtProperty: property,
				builtDeclaration: declaration,
				builtType: instantiable.concreteInstantiable,
				ownDependencies: instantiable.dependencies,
				children: propertiesToGenerate,
			)
			// Every label rebound is received in the body, so the walk meets each.
			self.reboundProperties = firstReceives.flatMap(\.value)
		} else {
			self.reboundProperties = []
		}
	}

	init(
		property: Property,
		fulfillingProperty: Property,
		fulfillingPropertyIsLazilyInstantiatedInstance: Bool,
		unavailableOptionalProperties: Set<Property>,
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
		receivedProperties = [fulfillingProperty]
		receivedOnlyByPublicMockCalls = []
		passedByPublicMockCalls = []
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
		reboundProperties = []
		description = property.asSource
		propertiesToGenerate = []
		propertiesToDeclare = []
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
		passedUpHoles = []
		valuesBindings = []
		isBuiltByFill = false
		containsBuildSite = false
		placeHoldingProperties = nil
		fieldsCarriedBySites = []
		passesUpBuilder = false
		fillKey = nil
		closedOnFillPathDeclarationsBeneath = nil
		fillStructBoundLabels = []
		fillFields = []
		fillCaseHoles = []
		fillEmitsCode = true
		fillCallerReads = FillCallerReads()
		fillDeferredLabelsHiddenByReenteringCalls = [:]
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
		reboundProperties = []
		description = holeProperty.asSource
		propertiesToGenerate = []
		propertiesToDeclare = []
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
		passedUpHoles = []
		valuesBindings = []
		isBuiltByFill = false
		containsBuildSite = true
		placeHoldingProperties = nil
		fieldsCarriedBySites = Set((site.map(Self.fieldsCarried(by:)) ?? []).map(\.property))
		passesUpBuilder = false
		fillKey = nil
		fillStructBoundLabels = []
		fillFields = []
		fillCaseHoles = []
		fillEmitsCode = true
		fillCallerReads = FillCallerReads()
		fillDeferredLabelsHiddenByReenteringCalls = [:]
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
			unavailableOptionalProperties: callerReads.unavailableProperties,
			lazilyInstantiatedInstanceProperties: [],
			forwardedLazilyInstantiatedInstanceProperties: [],
			erasedToConcreteExistential: false,
			isPropertyCycle: false,
			builtInlineSeamComment: nil,
			fill: (hole, key, functionName, boundLabels, fields, caseHoles, emitsCode, callerReads),
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
		/// The scope value the inner seam handed the fill, which a place inside its tree, or a call there that passes one up,
		/// carries (`SeamHoles.innerScope(at:innerKey:)`): the fill takes it as a parameter, and each dispatcher that leads to
		/// it passes it on from the root dispatcher's own parameter.
		var innerScopeParameters = [SeamSignature.Hole.Field]()
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
			return fieldsByProperty.values.sorted { first, second in
				switch (first.declarationLocation, second.declarationLocation) {
				case let (firstLocation?, secondLocation?) where firstLocation != secondLocation:
					firstLocation < secondLocation
				case (.some, .none):
					true
				case (.none, .some):
					false
				case (.some, .some), (.none, .none):
					first.property < second.property
				}
			}
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
		if let enumPlace = hole.enumPlace {
			// Joined unspelled, then spelled once: a seam's stem can be a raw identifier's text. A case nested in the root is
			// named after its enum too.
			let enumName = enumPlace.rootEnumTypeName == nil ? "" : "\(enumPlace.enumTypeName)_"
			return functionName(toBuildPropertyNamed: "\(hole.builderLabel.spelledWithoutBackticks)_\(DependencyTreeGenerator.seamStem(of: hole.scopeSeamType))_\(enumName)\(enumPlace.caseName.spelledWithoutBackticks)".spelledAsIdentifier)
		} else {
			return functionName(toBuildPropertyNamed: hole.builderLabel)
		}
	}

	/// What a seam call passes one builder: the label it takes it under and the expression passed.
	struct BuilderCallArgument: Sendable {
		init(label: String, value: String, enclosingFillKey: String? = nil, isSendable: Bool = false) {
			self.label = label
			self.value = value
			self.enclosingFillKey = enclosingFillKey
			self.isSendable = isSendable
		}

		let label: String
		let value: String
		/// The key of the enclosing fill or dispatcher passed by name, or `nil` when the call declares it or passes a builder up.
		let enclosingFillKey: String?
		/// Whether the seam takes the builder `@Sendable`.
		let isSendable: Bool
	}

	/// The function a caller generates over a seam's or a public mock's scope enum, which hands each case to the fill of its
	/// place or the dispatcher of the enum it holds. Each is a one-level switch, so a cycle of enums is ordinary mutual
	/// recursion. A public mock's caller fills some places of an enum and passes the others up: a dispatcher that reaches a
	/// place it does not fill takes `passUp`, which hands the builder the call passes up the whole scope the call was given.
	///
	/// Over an enum nested by type, a case carries what its type binds before the case's property, and the fill or
	/// dispatcher it hands its value to may read a value a type further out binds: that one takes it as a parameter, which
	/// each case that leads to it passes from its own payload, or, where its payload does not hold it, from the dispatcher's
	/// own parameter, so the value read is the one the nearest type on the actual route binds, as inline. The root
	/// dispatcher, which the builder is, takes none: a value no type on the route binds is the caller's own declaration of
	/// it, in scope where the dispatchers are declared. The parameters are found when the code is generated, from what the
	/// fills read (`dispatcherParameters(of:fillReads:)`), a fixed point over the enums, which can recurse.
	///
	/// A public mock's caller decides per route (`decidesPerRoute`): its fills read nothing of the caller's, so where the
	/// nearest type on the route binds no form of a value a fill reads that provides the form it reads, the case passes
	/// `nil`, and the fill is called only where every value it takes is there and the place passed up elsewhere (`RoutePlan`):
	/// the run-time twin of the per-place decision `holesFilled` makes, since the levels of a place, read nearest first, are
	/// its fields. A place inside a fill that one case of the called mock's enum leads to on several routes is filled on
	/// those that hold what its fill reads and passed up on the others (`PublicMockCall.sitesPassedUpOnSomeRoute`).
	struct FillDispatcher: Sendable {
		struct Case: Sendable {
			let name: String
			/// Whether a place's case carries a payload struct, which every case does but one of a `@Sendable` enum nested by
			/// type, whose place is held in a `Sendable` wrapper.
			var carriesPayload = true
			let hasForwardedValue: Bool
			/// The fill or dispatcher the case is handed to, or `nil` when every place it reaches is passed up.
			let target: Target?
			/// What the case carries before the value it hands on, in an enum nested by type: the fields of its payload.
			var values: [SeamSignature.Hole.Field]?
			/// For a call's case for a builder it fills (`SeamSignature.ScopeEnum.Case.Kind.fill`), whether the case carries the
			/// scope value the inner seam handed the fill, before the value it hands on, and the key of that value's enum, which a
			/// reader reads a value its target takes from (`InnerScopeReaders`).
			var isFillCase = false
			var carriedInnerKey: SeamSignature.ScopeEnum.Key?
			/// The labels a reader finds on every route of the inner seam's enum the case carries, which the case hands on
			/// whatever its own payload or this dispatcher's parameters hold.
			var labelsEveryInnerRouteHolds = Set<String>()
			/// The form the reader of each label a level of the inner seam's enum the case carries holds returns, which a caller
			/// that decides per route converts to the form a fill reads (`RoutePlan`).
			var innerReaderFormByLabel = [String: Property]()
			/// The labels the case's type binds from the case's property on, in an enum nested by type, which hide every value
			/// of the label a type further out binds (`SeamSignature.ScopeEnum.Values.labelsBoundLater`).
			var labelsBoundLater = Set<String>()

			/// The labels the case hands on from its payload: every field but one bound from a deferred parameter, whose
			/// memo inline never reads where the caller's own declaration is in scope.
			var carriedLabels: Set<String> {
				Set((values ?? []).filter { !$0.isDeferredParameter }.map(\.property.label))
			}

			struct Target: Sendable {
				let name: String
				let key: String
				/// Whether the target is a dispatcher that takes `passUp`.
				let takesPassUp: Bool
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
		/// For the dispatcher of a seam's root enum, the name of the scope value it is handed where a fill it leads to takes
		/// that value (`SeamHoles.innerScope(at:innerKey:)`): the dispatcher's parameter is named so, and every dispatcher and
		/// fill it leads to takes the value under it.
		var innerScopeName: String?
		/// The name of each reader of an inner seam's levels the call declares (`InnerScopeReaders`), the same for every
		/// dispatcher of the call.
		var readerNameByKey = [InnerScopeReaders.Key: String]()
		/// Whether the call is of a public mock, whose caller fills or passes up each place per route: a value a fill reads
		/// that a route's types do not bind is `nil` there, and the place is passed up on that route.
		var decidesPerRoute = false

		/// The parameters each dispatcher of `dispatchers` takes, by key, labeled and typed as the fields they pass on, in the
		/// order of their labels, given the fields each fill reads that its case's payload may not carry, by the fill's key.
		/// Found as a fixed point: a dispatcher takes each value a case's target reads that the case's payload does not
		/// carry, and a root dispatcher takes none.
		///
		/// A dispatcher's parameter of a label is typed from every form its targets take of it, transitively: a form that is
		/// no optional wins, since every route that reaches such a target hands it a value that is no optional, and an
		/// optional form takes the others; forms that still differ are chosen among in `Property` order, which
		/// per-place validation reports before code is generated. No form depends on the order the enums are met in.
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
						// A value a reader finds on every route of the inner seam's enum the case carries needs nothing further out.
						let carried = dispatcherCase.carriedLabels.union(dispatcherCase.labelsEveryInnerRouteHolds)
						for (label, forms) in formsByLabelByKey[target.key, default: [:]] where !carried.contains(label) {
							for (property, field) in forms where formsByLabelByKey[dispatcher.key]?[label]?[property] == nil {
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
				parametersByKey[dispatcher.key] = formsByLabel.keys.sorted().compactMap { label in
					let properties = formsByLabel[label, default: [:]].keys.sorted()
					let property = properties.first { !$0.typeDescription.isOptional } ?? properties.first
					return property.flatMap { formsByLabel[label]?[$0] }
				}
			}
			return parametersByKey
		}

		/// What the dispatchers of a call that decides per route take and hand on, and where each case finds each value
		/// (see `FillDispatcher.decidesPerRoute`).
		///
		/// A value is handed on in the form a fill reads (`Channel`): a fill takes each value it reads that its case's payload
		/// does not carry in the form it reads (`Scope.parameterField(of:reading:)`), and a dispatcher takes one parameter per
		/// label and form the fills and dispatchers beneath it read that its cases' payloads do not carry, so two fills that
		/// read two forms of one label, such as `Token` and `Token?`, each get their own. A case hands on the nearest value on
		/// the route: its payload's field, converted to the form, where that form is one the field provides
		/// (`CycleParameter.forms(providedBy:)`, the relation the per-place decision `holesFilled` fills by); `nil` where the
		/// payload holds the label in a form that does not provide it, or where the case's type binds the label from the
		/// case's property on, which hides every farther value; else the dispatcher's own parameter, which a root has none of.
		/// A parameter some case that leads to it may hand `nil` is optional, and a fill is called where every value it takes
		/// is there and the place passed up elsewhere. So a route is filled exactly where its place's nearest values provide
		/// what the fill reads, which is where the per-place decision fills it, or, for a place inside a fill whose routes
		/// through the called mock's tree differ, where it fills the place and passes it up too
		/// (`InnerScopeReaders.passesUpOnSomeInnerRoute(_:reading:from:)`).
		struct RoutePlan: Sendable {
			/// A value handed on: its label and the form a fill reads it in.
			struct Channel: Hashable, Comparable, Sendable {
				let label: String
				let type: TypeDescription

				static func < (lhs: Channel, rhs: Channel) -> Bool {
					(lhs.label, lhs.type.asSource) < (rhs.label, rhs.type.asSource)
				}
			}

			/// A parameter of a dispatcher: the value it takes, the name it takes it under, and whether it may be `nil`.
			struct Parameter: Sendable {
				let channel: Channel
				let name: String
				let isOptional: Bool
			}

			/// Where a case finds a value it hands on.
			enum Source {
				/// Its payload's field, in the form the expression spells.
				case payload(expression: String)
				/// The dispatcher's own parameter.
				case parameter(Parameter)
				/// Nowhere on this route: the case hands on `nil`.
				case none
			}

			/// The parameters of each dispatcher that decides per route, by key, in channel order.
			let parametersByKey: [String: [Parameter]]
			/// What each fill takes beside its case's payload, by key, in its parameters' order.
			let fillChannelsByKey: [String: [Channel]]

			init(of dispatchers: [FillDispatcher], fillParameters: [String: [SeamSignature.Hole.Field]]) {
				let perRouteDispatchers = dispatchers.filter(\.decidesPerRoute)
				var fillChannelsByKey = [String: [Channel]]()
				for (key, fields) in fillParameters {
					fillChannelsByKey[key] = fields.map { Channel(label: $0.property.label, type: $0.property.typeDescription) }
				}
				// A dispatcher nested in a root takes each value a case's target takes that the case's payload does not hold and
				// the case's type does not bind later.
				var channelsByKey = [String: Set<Channel>]()
				var changed = true
				while changed {
					changed = false
					for dispatcher in perRouteDispatchers where dispatcher.takesValuesOfOuterTypes {
						for dispatcherCase in dispatcher.cases {
							guard let target = dispatcherCase.target else { continue }
							// A value a reader finds on every route of the inner seam's enum a case carries needs nothing further out.
							let carried = Set((dispatcherCase.values ?? []).map(\.property.label)).union(dispatcherCase.labelsEveryInnerRouteHolds)
							for channel in fillChannelsByKey[target.key] ?? channelsByKey[target.key].map(Array.init) ?? []
								where !carried.contains(channel.label) && !dispatcherCase.labelsBoundLater.contains(channel.label)
							{
								if channelsByKey[dispatcher.key, default: []].insert(channel).inserted {
									changed = true
								}
							}
						}
					}
				}
				// A dispatcher's parameter is optional where some case that leads to it may hand on `nil`.
				var optionalChannelsByKey = [String: Set<Channel>]()
				changed = true
				while changed {
					changed = false
					for dispatcher in perRouteDispatchers {
						let ownChannels = channelsByKey[dispatcher.key] ?? []
						for dispatcherCase in dispatcher.cases {
							guard let target = dispatcherCase.target, fillChannelsByKey[target.key] == nil else { continue }
							for channel in channelsByKey[target.key] ?? [] where optionalChannelsByKey[target.key]?.contains(channel) != true {
								// What the case hands on where no level of the inner seam's enum it carries holds the value.
								let fallbackIsOptional = if let field = dispatcherCase.values?.first(where: { $0.property.label == channel.label }) {
									Self.expression(converting: field.property, to: channel, valuesName: "") == nil
								} else if dispatcherCase.labelsBoundLater.contains(channel.label) || !ownChannels.contains(channel) {
									true
								} else {
									optionalChannelsByKey[dispatcher.key]?.contains(channel) == true
								}
								let isOptional = if channel.label == dispatcher.innerScopeName {
									false
								} else if let readerForm = dispatcherCase.innerReaderFormByLabel[channel.label] {
									// A value a level of the inner seam's enum holds is the nearest on the routes that hold it.
									Self.conversion(of: "", from: readerForm, to: channel) == nil
										|| (!dispatcherCase.labelsEveryInnerRouteHolds.contains(channel.label) && fallbackIsOptional)
								} else {
									fallbackIsOptional
								}
								if isOptional {
									optionalChannelsByKey[target.key, default: []].insert(channel)
									changed = true
								}
							}
						}
					}
				}
				// Each value is taken under its label, and a second form of a label under a name allocated after it.
				var parametersByKey = [String: [Parameter]]()
				for (key, channels) in channelsByKey {
					let sortedChannels = channels.sorted()
					var usedNames = Set(sortedChannels.map(\.label))
					var labelsNamed = Set<String>()
					parametersByKey[key] = sortedChannels.map { channel in
						var name = channel.label
						if !labelsNamed.insert(channel.label).inserted {
							var index = 2
							repeat {
								name = "\(channel.label.spelledWithoutBackticks)_\(index)".spelledAsIdentifier
								index += 1
							} while usedNames.contains(name)
							usedNames.insert(name)
						}
						return Parameter(channel: channel, name: name, isOptional: optionalChannelsByKey[key]?.contains(channel) == true)
					}
				}
				self.parametersByKey = parametersByKey
				self.fillChannelsByKey = fillChannelsByKey
			}

			/// Where `dispatcherCase`, a case of `dispatcher`, finds `channel`, reading its payload as `valuesName`.
			func source(of channel: Channel, in dispatcherCase: Case, of dispatcher: FillDispatcher, valuesName: String) -> Source {
				if channel.label == dispatcher.innerScopeName {
					.parameter(Parameter(channel: channel, name: channel.label, isOptional: false))
				} else if let field = dispatcherCase.values?.first(where: { $0.property.label == channel.label }) {
					Self.expression(converting: field.property, to: channel, valuesName: valuesName).map { .payload(expression: $0) } ?? .none
				} else if dispatcherCase.labelsBoundLater.contains(channel.label) {
					.none
				} else if let parameter = parametersByKey[dispatcher.key]?.first(where: { $0.channel == channel }) {
					.parameter(parameter)
				} else {
					.none
				}
			}

			/// The keys of the fills whose body cannot be generated in the case that calls it: one the case calls only where a
			/// value is there, or hands a value other than the dispatcher's parameter of its label, which the body reads by name.
			func fillsNotInlinable(of dispatchers: [FillDispatcher]) -> Set<String> {
				var keys = Set<String>()
				for dispatcher in dispatchers where dispatcher.decidesPerRoute {
					for dispatcherCase in dispatcher.cases {
						guard let target = dispatcherCase.target, let channels = fillChannelsByKey[target.key] else { continue }
						let takesOnlyItsLabelsParameters = channels.allSatisfy { channel in
							if case let .parameter(parameter) = source(of: channel, in: dispatcherCase, of: dispatcher, valuesName: "") {
								!parameter.isOptional && parameter.name == channel.label
							} else {
								false
							}
						}
						if !takesOnlyItsLabelsParameters {
							keys.insert(target.key)
						}
					}
				}
				return keys
			}

			/// The expression that reads `field`, a payload's field, through `valuesName` in the form `channel` reads, or `nil`
			/// where the field does not provide that form.
			static func expression(converting field: Property, to channel: Channel, valuesName: String) -> String? {
				conversion(of: "\(valuesName).\(field.label.spelledAsMemberReference)", from: field, to: channel)
			}

			/// `value`, a value of `form`, in the form `channel` reads, or `nil` where `form` does not provide that form.
			static func conversion(of value: String, from form: Property, to channel: Channel) -> String? {
				let channelProperty = Property(label: channel.label, typeDescription: channel.type)
				guard CycleParameter.forms(providedBy: form).contains(channelProperty) else { return nil }
				if channelProperty == form || channelProperty == form.asOptionalProperty {
					return value
				} else {
					return "\(value).\(Dependency.lazilyInstantiatedInstancePropertyName)"
				}
			}
		}

		/// The name of a dispatcher's parameter that passes a place up, which no generated name can equal: every one begins
		/// with `__safeDI_`.
		static let passUpParameterName = "passUp"

		/// What identifies a dispatcher among the fills and dispatchers enclosing a call.
		static func key(of enumKey: SeamSignature.ScopeEnum.Key) -> String {
			"dispatcher \(enumKey.spelling)"
		}

		/// A dispatcher of an enum, for the routes of one family's root enum, or `nil` for one that serves every route that
		/// reaches the enum (see `dispatchers(of:filledSites:sitesPassedUpOnSomeRoute:enclosingDispatchers:fillNames:names:innerScopeNameByKey:decidesPerRoute:)`).
		struct Instance: Hashable {
			let enumKey: SeamSignature.ScopeEnum.Key
			/// Whether the routes are the `@Sendable` root enum's, where the instance serves one family.
			let family: Bool?

			/// The key that identifies the dispatcher: the enum's, and, for an enum with a dispatcher for each family, the
			/// family's.
			func dispatcherKey(isSplit: Bool) -> String {
				guard isSplit, let family else { return FillDispatcher.key(of: enumKey) }
				return "\(FillDispatcher.key(of: enumKey)) on the \(family ? "@Sendable" : "plain") routes"
			}
		}

		/// The dispatchers a call that passes `calledBuilders` and fills the places of `filledSites` declares, in the order
		/// its arguments first reach them with an explicit stack: one for each enum that reaches a filled place, which no
		/// enclosing call declares.
		///
		/// A public mock's caller passes up a place it does not fill on every route, so a dispatcher that reaches one takes
		/// `passUp`. The plain and the `@Sendable` root enum of a hole type hold the same enums nested by type, but each one's
		/// routes reach only its own places (`CalledBuilders.sitesReachedOnItsRoutes(by:in:)`): an enum whose places on the
		/// routes of one root are all filled and on the other's are not has a dispatcher for each, so the builder of the root
		/// whose routes fill every place takes no `passUp`, and the caller no builder to pass up.
		/// - Parameters:
		///   - sitesPassedUpOnSomeRoute: The sites among `filledSites` a public mock's caller passes up on some route too
		///     (`PublicMockCall.sitesPassedUpOnSomeRoute`).
		///   - decidesPerRoute: Whether the call is of a public mock (see `FillDispatcher.decidesPerRoute`).
		static func dispatchers(
			of calledBuilders: CalledBuilders,
			filledSites: Set<SeamSignature.Hole.Site>,
			sitesPassedUpOnSomeRoute: Set<SeamSignature.Hole.Site> = [],
			enclosingDispatchers: [String: String],
			fillNames: [String: String],
			names: inout GeneratedNameAllocator,
			innerScopeNameByKey: [SeamSignature.ScopeEnum.Key: String] = [:],
			decidesPerRoute: Bool = false,
		) -> [FillDispatcher] {
			let enumsByKey = calledBuilders.enumsByKey
			let holesBySite = Dictionary(calledBuilders.holes.map { ($0.site, $0) }, uniquingKeysWith: { first, _ in first })
			let sitesFilledOnEveryRoute = filledSites.subtracting(sitesPassedUpOnSomeRoute)
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
					      enclosingDispatchers[Self.key(of: key)] == nil,
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
				!sitesReached(from: key, onRoutesOf: family).isSubset(of: sitesFilledOnEveryRoute)
			}
			// An enum both families reach has a dispatcher for each where one takes `passUp` and the other does not; otherwise
			// one serves both.
			var instancesToDeclare = [Instance]()
			var splitKeys = Set<SeamSignature.ScopeEnum.Key>()
			for key in reachedKeys {
				let families = familiesByKey[key] ?? []
				if decidesPerRoute, families.count > 1, Set(families.map { takesPassUp(key, onRoutesOf: $0) }).count > 1 {
					splitKeys.insert(key)
					instancesToDeclare += families.map { Instance(enumKey: key, family: $0) }
				} else {
					instancesToDeclare.append(Instance(enumKey: key, family: families.count == 1 ? families.first : nil))
				}
			}
			/// The instance a case of a dispatcher for `family`'s routes hands the enum of `key` to.
			func targetInstance(of key: SeamSignature.ScopeEnum.Key, onRoutesOf family: Bool?) -> Instance {
				if splitKeys.contains(key), let family {
					Instance(enumKey: key, family: family)
				} else {
					Instance(enumKey: key, family: familiesByKey[key]?.count == 1 ? familiesByKey[key]?.first : nil)
				}
			}
			// The builder label of each family's root enum of a hole type, which names a dispatcher for that family's routes.
			var rootBuilderLabelByFamily = [SeamSignature.HoleType: [Bool: String]]()
			for builder in calledBuilders.builders {
				rootBuilderLabelByFamily[builder.enumKey.holeType, default: [:]][builder.enumKey.isSendable] = enumsByKey[builder.enumKey]?.builderLabel
			}
			var dispatcherNames = enclosingDispatchers
			for instance in instancesToDeclare {
				guard let scopeEnum = enumsByKey[instance.enumKey] else { continue }
				// An enum nested by type is named after its own enum too, and a dispatcher for one family's routes of an enum
				// both reach after that family's builder.
				let enumName = scopeEnum.rootTypeName == nil ? "" : "_\(scopeEnum.typeName)"
				let builderLabel = splitKeys.contains(instance.enumKey)
					? instance.family.flatMap { rootBuilderLabelByFamily[instance.enumKey.holeType]?[$0] } ?? scopeEnum.builderLabel
					: scopeEnum.builderLabel
				dispatcherNames[instance.dispatcherKey(isSplit: splitKeys.contains(instance.enumKey))] = names.claim(ScopeGenerator.functionName(toBuildPropertyNamed: "\(builderLabel.spelledWithoutBackticks)_\(DependencyTreeGenerator.seamStem(of: instance.enumKey.seamType))\(enumName)".spelledAsIdentifier))
			}
			// The places a case nested by type stands for are filled by the fill of the first that the builders reach.
			let holeIndexBySite = Dictionary(calledBuilders.holes.enumerated().map { ($0.element.site, $0.offset) }, uniquingKeysWith: { first, _ in first })
			let dispatchers = instancesToDeclare.compactMap { instance -> FillDispatcher? in
				let key = instance.enumKey
				let family = instance.family
				guard let scopeEnum = enumsByKey[key] else { return nil }
				let cases = scopeEnum.cases.compactMap { enumCase -> Case? in
					switch enumCase.kind {
					case let .place(sites):
						let rootKey = decidesPerRoute ? family.flatMap { rootKey(ofFamily: $0, holeType: key.holeType) } : nil
						let sitesOnRoutes = rootKey.map { CalledBuilders.sites(Set(sites), onRoutesOf: $0, holeBySite: holesBySite) } ?? Set(sites)
						guard let site = sites.filter({ filledSites.contains($0) && sitesOnRoutes.contains($0) }).min(by: { holeIndexBySite[$0, default: .max] < holeIndexBySite[$1, default: .max] }),
						      let hole = holesBySite[site]
						else {
							let firstHole = sites.first.flatMap { holesBySite[$0] }
							return Case(name: enumCase.name, carriesPayload: enumCase.values != nil, hasForwardedValue: firstHole?.forwardedType != nil, target: nil, values: enumCase.values?.fields, labelsBoundLater: enumCase.values?.labelsBoundLater ?? [])
						}
						let targetKey = ScopeGenerator.fillKey(of: hole)
						return Case(name: enumCase.name, carriesPayload: enumCase.values != nil, hasForwardedValue: hole.forwardedType != nil, target: Case.Target(name: fillNames[targetKey] ?? "", key: targetKey, takesPassUp: false), values: enumCase.values?.fields, labelsBoundLater: enumCase.values?.labelsBoundLater ?? [])
					case let .nested(innerKey, _),
					     let .inner(innerKey, _, _),
					     let .fill(_, _, innerKey, _):
						// The routes this dispatcher serves reach the places of the enum the case holds that are on them.
						let reachedSites = sitesReached(from: innerKey, onRoutesOf: family)
						let target = targetInstance(of: innerKey, onRoutesOf: family)
						var dispatcherCase = Case(name: enumCase.name, hasForwardedValue: false, target: nil, values: enumCase.values?.fields, labelsBoundLater: enumCase.values?.labelsBoundLater ?? [])
						if case .fill = enumCase.kind {
							dispatcherCase.isFillCase = true
							dispatcherCase.carriedInnerKey = SeamSignature.ScopeEnum.carriedInnerKey(of: enumCase)
						}
						guard !reachedSites.isDisjoint(with: filledSites) else { return dispatcherCase }
						let targetKey = target.dispatcherKey(isSplit: splitKeys.contains(innerKey))
						return Case(
							name: dispatcherCase.name,
							hasForwardedValue: false,
							target: Case.Target(name: dispatcherNames[targetKey] ?? "", key: targetKey, takesPassUp: takesPassUp(innerKey, onRoutesOf: target.family)),
							values: dispatcherCase.values,
							isFillCase: dispatcherCase.isFillCase,
							carriedInnerKey: dispatcherCase.carriedInnerKey,
							labelsBoundLater: dispatcherCase.labelsBoundLater,
						)
					}
				}
				let dispatcherKey = instance.dispatcherKey(isSplit: splitKeys.contains(key))
				var dispatcher = FillDispatcher(
					key: dispatcherKey,
					functionName: dispatcherNames[dispatcherKey] ?? "",
					enumType: scopeEnum.type,
					// The first place of the hole type in the order the builders reach them: `holes` is ordered, so the spelling
					// never depends on a dictionary's order when places spell one type differently.
					returnType: calledBuilders.holes.first { $0.holeType == key.holeType }?.builtType ?? key.holeType.builtType,
					isSendableFamily: key.isSendable,
					takesPassUp: takesPassUp(key, onRoutesOf: family),
					cases: cases,
				)
				dispatcher.takesValuesOfOuterTypes = key.describedType != nil
				dispatcher.innerScopeName = key.describedType == nil ? innerScopeNameByKey[key] : nil
				dispatcher.decidesPerRoute = decidesPerRoute
				return dispatcher
			}
			// The readers a case of a call's fill reads an inner seam's levels through, named after every dispatcher.
			let readerNameByKey = InnerScopeReaders.claimNames(
				forValuesCarriedBy: reachedKeys.flatMap { enumsByKey[$0]?.cases ?? [] },
				enumsByKey: enumsByKey,
				names: &names,
			)
			guard !readerNameByKey.isEmpty else { return dispatchers }
			let readers = InnerScopeReaders(enumsByKey: enumsByKey, nameByKey: readerNameByKey)
			return dispatchers.map { dispatcher in
				var dispatcher = dispatcher
				dispatcher.readerNameByKey = readerNameByKey
				dispatcher.cases = dispatcher.cases.map { dispatcherCase in
					var dispatcherCase = dispatcherCase
					if let innerKey = dispatcherCase.carriedInnerKey {
						dispatcherCase.labelsEveryInnerRouteHolds = readers.labelsEveryRouteHolds(from: innerKey)
						dispatcherCase.innerReaderFormByLabel = readers.formByLabel(from: innerKey)
					}
					return dispatcherCase
				}
				return dispatcher
			}
		}

		/// The body of a fill generated in the one case of a dispatcher that calls it, in place of a function of its own
		/// (see `ScopeGenerator.inlinableFillKeys`): what the case binds, and the fill's body, indented for the case.
		struct InlinedFill {
			/// Whether the case carries a payload struct, which the fill is handed as its scope.
			var carriesPayload = true
			/// Whether the body reads the scope; a case that binds a value it never reads draws a warning.
			let readsScope: Bool
			/// The name the fill's function gives the value an instantiator forwards, or `nil` for a place that forwards none.
			let forwardedValueName: String?
			/// Whether the body reads the forwarded value: a fill never reads a forwarded `Void`.
			let readsForwardedValue: Bool
			let body: [String]
		}

		/// The function, indented by `indent`, `@Sendable` as `isSendable` says. A case whose fill is in `inlinedFills`, by
		/// key, holds the fill's body; every other case returns what the function it hands its payload to returns.
		/// - Parameters:
		///   - parametersByKey: What each dispatcher of the call takes beside its enum (`dispatcherParameters(of:fillReads:)`),
		///     and each fill nested by type beside its case's payload, by key.
		///   - routePlan: What each dispatcher that decides per route takes and hands on (`RoutePlan`).
		/// - Throws: `publicMockRouteWithoutPassUp` where a dispatcher that decides per route would pass a place up on a route
		///   but takes no `passUp`.
		func declaration(
			isSendable: Bool,
			indent: String,
			inlinedFills: [String: InlinedFill],
			parametersByKey: [String: [SeamSignature.Hole.Field]] = [:],
			callerArgumentByLabel: [String: String] = [:],
			routePlan: RoutePlan? = nil,
			typesDeclaredEscaping: Set<TypeDescription> = [],
			readers: InnerScopeReaders? = nil,
		) throws -> String {
			let caseIndent = indent + ScopeGenerator.standardIndent
			// What this function hands on of a value no case carries: its own parameter, or, for the root dispatcher, which
			// takes none, the caller's declaration in the form the target takes (`ScopeGenerator.FillCallerReads`).
			func ownValue(of label: String) -> String {
				takesValuesOfOuterTypes ? label : callerArgumentByLabel[label] ?? label
			}
			let forwarded = ReservedName.forwardedValueParameterName
			let passUp = Self.passUpParameterName
			let parameters = parametersByKey[key] ?? []
			let routeParameters = decidesPerRoute ? routePlan?.parametersByKey[key] ?? [] : []
			// The names this function binds, apart from the labels of what it takes and passes on.
			var labels = Set(parameters.map(\.property.label) + cases.flatMap { dispatcherCase in
				dispatcherCase.target.flatMap { parametersByKey[$0.key] }?.map(\.property.label) ?? []
			})
			if decidesPerRoute, let routePlan {
				labels.formUnion(routeParameters.map(\.name))
				for dispatcherCase in cases {
					guard let target = dispatcherCase.target else { continue }
					labels.formUnion((routePlan.parametersByKey[target.key] ?? []).map(\.name))
					labels.formUnion((routePlan.fillChannelsByKey[target.key] ?? []).map(\.label))
				}
			}
			func name(_ base: String) -> String {
				var name = base
				while labels.contains(name) {
					name += "_"
				}
				return name
			}
			let scopeName = name("scope")
			let valuesName = name("values")
			let innerScopeBindingName = name("innerScope")
			// The dispatcher a builder is takes the scope value it is handed under the name every fill and dispatcher it leads
			// to takes it, where one does.
			let parameterName = innerScopeName.flatMap { innerScopeName in
				cases.contains { dispatcherCase in
					guard let target = dispatcherCase.target else { return false }
					var labels = (parametersByKey[target.key] ?? []).map(\.property.label)
					if decidesPerRoute {
						labels += (routePlan?.parametersByKey[target.key] ?? []).map(\.channel.label)
					}
					return labels.contains(innerScopeName)
				} ? innerScopeName : nil
			} ?? scopeName
			/// The line of a case that passes its place up, which only a dispatcher handed `passUp` can.
			func passUpLine(of dispatcherCase: Case) throws -> String {
				guard takesPassUp else {
					throw DependencyTreeGenerator.DependencyTreeGeneratorError.publicMockRouteWithoutPassUp(.init(enumType: enumType, caseName: dispatcherCase.name))
				}
				return "\(caseIndent)case .\(dispatcherCase.name): return \(passUp)()"
			}
			var caseLines = [String]()
			for dispatcherCase in cases {
				if let target = dispatcherCase.target, dispatcherCase.isFillCase {
					// A call's case for a builder it fills hands on the enum of the fill's type and each value that one reads: the
					// nearest of the inner seam's levels that holds it, through a reader, else this case's payload's field, else
					// this function's own value.
					let carried = dispatcherCase.carriedLabels
					var readsValues = false
					var readsInnerScope = false
					var arguments = ""
					if decidesPerRoute, let routePlan {
						// A caller that decides per route hands on each value in the form the target takes it: the nearest of the inner
						// seam's levels that holds it, through a reader, converted to that form, else what the route finds of it
						// (`RoutePlan.source`), `nil` where it finds none, so the place is passed up there.
						for targetParameter in routePlan.parametersByKey[target.key] ?? [] {
							let channel = targetParameter.channel
							var fallback: String?
							var fallbackReadsValues = false
							switch routePlan.source(of: channel, in: dispatcherCase, of: self, valuesName: valuesName) {
							case let .payload(expression):
								fallback = expression
								fallbackReadsValues = true
							case let .parameter(parameter):
								fallback = parameter.name
							case .none:
								fallback = nil
							}
							var value = fallback ?? "nil"
							var readsFallback = true
							if let innerKey = dispatcherCase.carriedInnerKey,
							   let readerForm = dispatcherCase.innerReaderFormByLabel[channel.label],
							   let call = readers?.readerCall(of: channel.label, from: innerKey, handing: innerScopeBindingName)
							{
								if let converted = RoutePlan.conversion(of: "$0", from: readerForm, to: channel) {
									readsInnerScope = true
									if dispatcherCase.labelsEveryInnerRouteHolds.contains(channel.label) {
										// A reader that finds a value on every route returns it.
										readsFallback = false
										value = RoutePlan.conversion(of: call, from: readerForm, to: channel) ?? call
									} else {
										// A reader returns `nil` on a route no level of which holds the value.
										let read = converted == "$0" && readerForm.typeDescription == channel.type
											? call
											: "\(call).map { \(converted) as \(channel.type.asSource) }"
										value = fallback.map { "\(read) ?? \($0)" } ?? read
									}
								} else if !dispatcherCase.labelsEveryInnerRouteHolds.contains(channel.label), let fallback {
									// A level of the inner seam's that holds the value in a form that does not provide the one read hides every
									// value further out, as inline's lookup does: only a route whose reader finds none hands on the fallback.
									readsInnerScope = true
									value = "\(call) == nil ? \(fallback) : nil"
								} else {
									readsFallback = false
									value = "nil"
								}
							}
							readsValues = readsValues || (fallbackReadsValues && readsFallback)
							arguments += ", \(targetParameter.name.spelledAsArgumentLabel): \(value)"
						}
					} else {
						arguments = (parametersByKey[target.key] ?? []).map { parameter in
							let label = parameter.property.label
							var value = ownValue(of: label)
							let readsOwnPayload = carried.contains(label)
							if readsOwnPayload {
								value = "\(valuesName).\(label.spelledAsMemberReference)"
							}
							// The payload's field is read only where the reader falls back to it: a value the reader finds on every route
							// leaves the payload unbound.
							if let innerKey = dispatcherCase.carriedInnerKey, let call = readers?.call(of: label, from: innerKey, handing: innerScopeBindingName, fallback: value) {
								readsInnerScope = true
								readsValues = readsValues || (readsOwnPayload && call.readsFallback)
								value = call.expression
							} else {
								readsValues = readsValues || readsOwnPayload
							}
							return ", \(label.spelledAsArgumentLabel): \(value)"
						}.joined()
					}
					var bound = [String]()
					if dispatcherCase.values != nil {
						bound.append(readsValues ? valuesName : "_")
					}
					if dispatcherCase.carriedInnerKey != nil {
						bound.append(readsInnerScope ? innerScopeBindingName : "_")
					}
					bound.append(scopeName)
					let passUpArgument = target.takesPassUp ? ", \(passUp): \(passUp)" : ""
					caseLines.append("\(caseIndent)case let .\(dispatcherCase.name)(\(bound.joined(separator: ", "))): return \(target.name)(\(scopeName)\(arguments)\(passUpArgument))")
				} else if let target = dispatcherCase.target, let inlinedFill = inlinedFills[target.key] {
					// A value the body never reads is matched by `_`, and a case that reads none binds nothing.
					var bindings = inlinedFill.carriesPayload ? [inlinedFill.readsScope ? "scope" : "_"] : []
					if let forwardedValueName = inlinedFill.forwardedValueName {
						bindings.append(inlinedFill.readsForwardedValue ? forwardedValueName : "_")
					}
					if bindings.allSatisfy({ $0 == "_" }) {
						caseLines.append("\(caseIndent)case .\(dispatcherCase.name):")
					} else {
						caseLines.append("\(caseIndent)case let .\(dispatcherCase.name)(\(bindings.joined(separator: ", "))):")
					}
					caseLines += inlinedFill.body
				} else if let target = dispatcherCase.target {
					let passUpArgument = target.takesPassUp ? ", \(passUp): \(passUp)" : ""
					let targetParameters = parametersByKey[target.key] ?? []
					if decidesPerRoute, let routePlan, let channels = routePlan.fillChannelsByKey[target.key] {
						// A fill nested by type takes each value it reads that its case's payload does not carry, in the form it reads:
						// where a route may lack one, the fill is called only where every such value is there, and the place is passed
						// up elsewhere, as the per-place decision passes up the place of a route that lacks it.
						var arguments = ""
						var unwrappedNames = [String]()
						var lacksAValue = false
						for channel in channels {
							// The case's payload is the place's own, which the fill is handed as its scope.
							switch routePlan.source(of: channel, in: dispatcherCase, of: self, valuesName: scopeName) {
							case let .payload(expression):
								arguments += ", \(channel.label.spelledAsArgumentLabel): \(expression)"
							case let .parameter(parameter):
								if parameter.isOptional {
									unwrappedNames.append(parameter.name)
								}
								arguments += ", \(channel.label.spelledAsArgumentLabel): \(parameter.name)"
							case .none:
								lacksAValue = true
							}
						}
						if lacksAValue {
							try caseLines.append(passUpLine(of: dispatcherCase))
						} else {
							let pattern = dispatcherCase.hasForwardedValue
								? "case let .\(dispatcherCase.name)(\(scopeName), \(forwarded)):"
								: "case let .\(dispatcherCase.name)(\(scopeName)):"
							let call = dispatcherCase.hasForwardedValue
								? "\(target.name)(\(scopeName), \(forwarded)\(arguments))"
								: "\(target.name)(\(scopeName)\(arguments))"
							if unwrappedNames.isEmpty {
								caseLines.append("\(caseIndent)\(pattern) return \(call)")
							} else if takesPassUp {
								let bindings = unwrappedNames.map { "let \($0)" }.joined(separator: ", ")
								caseLines.append("\(caseIndent)\(pattern) if \(bindings) { return \(call) } else { return \(passUp)() }")
							} else {
								try caseLines.append(passUpLine(of: dispatcherCase))
							}
						}
					} else if Self.isFill(target) {
						// A fill nested by type takes each value it reads that its case's payload does not carry, under its label:
						// this function's own, or the caller's.
						var bound = dispatcherCase.carriesPayload ? [scopeName] : []
						if dispatcherCase.hasForwardedValue {
							bound.append(forwarded)
						}
						let arguments = (bound + targetParameters.map { "\($0.property.label.spelledAsArgumentLabel): \(ownValue(of: $0.property.label))" }).joined(separator: ", ")
						caseLines.append(bound.isEmpty
							? "\(caseIndent)case .\(dispatcherCase.name): return \(target.name)(\(arguments))"
							: "\(caseIndent)case let .\(dispatcherCase.name)(\(bound.joined(separator: ", "))): return \(target.name)(\(arguments))")
					} else if decidesPerRoute, let routePlan {
						// A case nested by type hands its dispatcher the value it wraps and each value that one takes: this case's
						// payload's, in the form taken, `nil` where the route does not bind it in that form, or this function's own. A
						// case of a `@Sendable` enum carries no payload.
						var readsValues = false
						var arguments = ""
						for targetParameter in routePlan.parametersByKey[target.key] ?? [] {
							let value: String
							switch routePlan.source(of: targetParameter.channel, in: dispatcherCase, of: self, valuesName: valuesName) {
							case let .payload(expression):
								readsValues = true
								value = expression
							case let .parameter(parameter):
								value = parameter.name
							case .none:
								value = "nil"
							}
							arguments += ", \(targetParameter.name.spelledAsArgumentLabel): \(value)"
						}
						let bound = dispatcherCase.values == nil ? scopeName : "\(readsValues ? valuesName : "_"), \(scopeName)"
						caseLines.append("\(caseIndent)case let .\(dispatcherCase.name)(\(bound)): return \(target.name)(\(scopeName)\(arguments)\(passUpArgument))")
					} else if dispatcherCase.values != nil || !targetParameters.isEmpty {
						// A case nested by type hands its dispatcher the value it wraps and each value that one reads, from this case's
						// payload where it carries one: a case of a `@Sendable` enum carries none.
						let carried = dispatcherCase.carriedLabels
						let arguments = targetParameters.map { parameter in
							let label = parameter.property.label
							return ", \(label.spelledAsArgumentLabel): \(carried.contains(label) ? "\(valuesName).\(label.spelledAsMemberReference)" : ownValue(of: label))"
						}.joined()
						let readsValues = targetParameters.contains { carried.contains($0.property.label) }
						let bound = dispatcherCase.values == nil ? scopeName : "\(readsValues ? valuesName : "_"), \(scopeName)"
						caseLines.append("\(caseIndent)case let .\(dispatcherCase.name)(\(bound)): return \(target.name)(\(scopeName)\(arguments)\(passUpArgument))")
					} else {
						caseLines.append("\(caseIndent)case let .\(dispatcherCase.name)(\(scopeName)): return \(target.name)(\(scopeName)\(passUpArgument))")
					}
				} else if decidesPerRoute {
					try caseLines.append(passUpLine(of: dispatcherCase))
				} else {
					caseLines.append("\(caseIndent)case .\(dispatcherCase.name): return \(passUp)()")
				}
			}
			let passUpParameter = takesPassUp ? ", \(passUp): () -> \(returnType.asSource)" : ""
			let valueParameters = if decidesPerRoute {
				routeParameters.map { parameter in
					let type = parameter.isOptional
						? TypeDescription.optional(parameter.channel.type)
						: parameter.channel.type.asFunctionParameter(amongTypesDeclaredEscaping: typesDeclaredEscaping)
					return ", \(parameter.name.spelledAsArgumentLabel): \(type.asSource)"
				}.joined()
			} else {
				parameters.map { ", \($0.property.label.spelledAsArgumentLabel): \($0.property.typeDescription.asFunctionParameter(amongTypesDeclaredEscaping: typesDeclaredEscaping).asSource)" }.joined()
			}
			var lines = ["\(indent)\(isSendable ? "@Sendable " : "")func \(functionName)(_ \(parameterName): \(enumType.asSource)\(valueParameters)\(passUpParameter)) -> \(returnType.asSource) {", "\(caseIndent)switch \(parameterName) {"]
			lines += caseLines
			lines += ["\(caseIndent)}", "\(indent)}"]
			return lines.joined(separator: "\n")
		}

		/// Whether `target` is a fill rather than a dispatcher.
		private static func isFill(_ target: Case.Target) -> Bool {
			!target.key.hasPrefix("dispatcher ")
		}

		/// The readers each call's case for a builder it fills reads through for what its target takes, given the parameters
		/// each target takes, by key: each reader once, in case order.
		/// A dispatcher that decides per route reads for what its target takes per route (`routePlan`).
		func readerRequests(parametersByKey: [String: [SeamSignature.Hole.Field]], routePlan: RoutePlan?, readers: InnerScopeReaders) -> [InnerScopeReaders.Key] {
			cases.flatMap { dispatcherCase -> [InnerScopeReaders.Key] in
				guard let innerKey = dispatcherCase.carriedInnerKey, let target = dispatcherCase.target else { return [] }
				let labels = if decidesPerRoute, let routePlan {
					(routePlan.parametersByKey[target.key] ?? []).map(\.channel.label)
				} else {
					(parametersByKey[target.key] ?? []).map(\.property.label)
				}
				return labels.compactMap { label in
					let key = InnerScopeReaders.Key(enumKey: innerKey, label: label)
					return readers.call(of: key.label, from: innerKey, handing: "", fallback: "") == nil ? nil : key
				}
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
		if hole.enumPlace != nil {
			// The case of a place nested by type is shared by every place of its type's property.
			"\(fillCaseKey(of: hole)) \(hole.sitePath.map(\.asSource).joined(separator: " "))"
		} else {
			fillCaseKey(of: hole)
		}
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
								generics: [parameter.deferredValueType],
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
			VisibleDeclaration(
				property: property,
				instanceProperty: instanceProperty,
				// A property a mock root promotes is declared by no type of the tree.
				declaringType: declarationLocationByProperty[property] == nil && !isFill ? nil : declaringType,
				declarationLocation: declarationLocationByProperty[property] ?? scopeDeclarationLocation,
				sendableBuilderDepth: 0,
			)
		}
		var scopeDeclarationsByLabel = [String: [VisibleDeclaration]]()
		for dependency in dependencies where dependency.source == .forwarded {
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
			if let declarations = declarationsByLabel[receivedProperty.label] {
				let unwrappedReceivedProperty = receivedProperty.asUnwrappedProperty
				guard let declaration = declarations.first(where: {
				      	$0.property.asUnwrappedProperty == unwrappedReceivedProperty || $0.instanceProperty?.asUnwrappedProperty == unwrappedReceivedProperty
				      }),
				      declaration.property.propertyType.isNonSendableWrapper,
				      declaration.sendableBuilderDepth < sendableBuilderDepth
				else { return nil }
				wrapperProperty = declaration.property
				wrapperDeclaration = declaration
				capturingBuilder = enclosingSendableBuilders[declaration.sendableBuilderDepth]
			} else if receivedProperty.propertyType.isNonSendableWrapper {
				// No scope in the tree declares the label, so this is a mock, which declares the property at its root.
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
	/// For a scope that calls a seam, the builders the call passes, in builder-label order; empty otherwise.
	private let holeCallArguments: [HoleCallArgument]
	/// What this scope's seam call passes each builder, in the order the seam takes them.
	private let builderCallArguments: [BuilderCallArgument]
	/// The dispatchers this scope's seam call declares.
	private let fillDispatchers: [FillDispatcher]
	/// For a scope that calls a seam, the holes of that seam whose builders the call passes up from the builders of
	/// the seam whose tree makes the call, in builder-label order: the caller's declarations hold no type that fulfills
	/// them. Empty otherwise.
	let passedUpHoles: [SeamSignature.Hole]
	/// Whether a scope in this generator's subtree passes up a builder (see `passedUpHoles`).
	let passesUpBuilder: Bool
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
	/// Whether a fill in this subtree binds other fields from its struct than its call's
	/// `fillDeferredLabelsHiddenByReenteringCalls` ask, which another pass of `Scope.createScopeGenerator` corrects.
	let fillStructBoundLabelsChangedInTree: Bool

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
	/// Whether a fill builds this scope's property: the fill returns the value a builder returns, so a wrapper's scope
	/// declares its builder function and returns what the function builds, and leaves the wrapper to the seam.
	private let isBuiltByFill: Bool
	/// See `MockParameterNode.valuesBindings`: each field read as the scope's parent reads its label, as production's are.
	nonisolated var valuesBindingsBeforeBuilderFunction: [String] {
		valuesBindings.map { $0.line(readingInstancesOf: callSiteLazilyInstantiatedInstanceProperties) }
	}

	/// Whether this scope's generated subtree holds a site of a hole of the seam whose tree is generated, on this scope's
	/// path. A child starts after its siblings that hold no place by `startsAsCarrier(_:)`, which reads this only where
	/// `placeHoldingProperties` is `nil` (see `orderedPropertyToGenerateIndices`).
	let containsBuildSite: Bool
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

	/// Whether this scope's call of another module's public mock passes a fill or a dispatcher, its own or an enclosing
	/// call's, which the node that makes the call declares in a builder function of its own.
	nonisolated var fillsABuilder: Bool {
		publicMockCall != nil
			&& (!fillDispatchers.isEmpty || propertiesToGenerate.contains { $0.fillKey != nil } || builderCallArguments.contains { $0.enclosingFillKey != nil })
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
	func prepareFillCode(propertiesGeneratedLater: Set<Property>) async throws {
		fillCodeByPropertiesGeneratedLater[propertiesGeneratedLater] = try await generateProperties(
			propertiesGeneratedLater: propertiesGeneratedLater,
			enclosingFunctionNames: [:],
			leadingMemberWhitespace: "",
		)
	}

	/// The code of the fills `prepareFillCode(propertiesGeneratedLater:)` generated with `propertiesGeneratedLater`.
	func fillCode(propertiesGeneratedLater: Set<Property>) -> [String] {
		fillCodeByPropertiesGeneratedLater[propertiesGeneratedLater, default: []]
	}

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
	private var orderedPropertiesToGenerate: LazyMapSequence<[Int], ScopeGenerator> {
		orderedPropertyToGenerateIndices.lazy.map { self.propertiesToGenerate[$0] }
	}

	/// The indices in `propertiesToGenerate` of `orderedPropertiesToGenerate`. Kept as indices so that
	/// `propertiesToGenerate` holds the only references this generator has to its children (see `deinit`).
	private lazy var orderedPropertyToGenerateIndices: [Int] = computeOrderedPropertyToGenerateIndices()

	/// `orderedPropertyToGenerateIndices`, computed afresh, which reads nothing but what the generator and its
	/// children hold from their creation, so a walk of a seam's tree can order a scope's children without awaiting it.
	nonisolated func computeOrderedPropertyToGenerateIndices() -> [Int] {
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
		let startIndices: [Int] = if propertiesToGenerate.contains(where: startsAsCarrier) {
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
			// A required optional property can resolve to a sibling of its non-optional form:
			// in a mock, or through an `onlyIfAvailable` receive of it above the receiver.
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
	/// order. The second takes every receive the first left `nil` whose receiver and received sibling are both builders, adds
	/// them all to the graph at once, and gives each one exactly when its strongly connected component holds only builders,
	/// so it reads no order: renaming or reordering cannot change it.
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
		var arrows = siblingGraph.dependencies
		var selfArrows = siblingGraph.childrenRequiringThemselves
		for candidate in candidates {
			if candidate.receiver == candidate.sibling {
				selfArrows.insert(candidate.receiver)
			} else {
				arrows[candidate.receiver].insert(candidate.sibling)
			}
		}
		let componentByIndex = stronglyConnectedComponents(of: arrows)
		var componentHoldsOnlyBuilders = [Int: Bool]()
		for index in children.indices {
			componentHoldsOnlyBuilders[componentByIndex[index], default: true] = componentHoldsOnlyBuilders[componentByIndex[index], default: true] && isBuilder[index]
		}
		func isOnLoop(_ index: Int) -> Bool {
			componentHoldsOnlyBuilders[componentByIndex[index]] == true
		}
		// A candidate is given when its component holds only builders; every other one stays `nil`.
		var givenCandidates = Set<Int>()
		var givenSelfArrows = siblingGraph.childrenRequiringThemselves
		for candidate in candidates where componentByIndex[candidate.receiver] == componentByIndex[candidate.sibling] && isOnLoop(candidate.receiver) {
			if candidate.receiver == candidate.sibling {
				givenSelfArrows.insert(candidate.receiver)
			} else {
				givenCandidates.insert(candidate.receiver * children.count + candidate.sibling)
			}
		}
		var loops = ReceivedBuilderLoops()
		for index in children.indices where isOnLoop(index) {
			var reboundProperties = Set<Property>()
			for siblingIndex in siblingGraph.dependencies[index] where componentByIndex[siblingIndex] == componentByIndex[index] {
				if let property = children[siblingIndex].property {
					reboundProperties.insert(property)
				}
			}
			for candidate in candidates
				where candidate.receiver == index && candidate.sibling != index && givenCandidates.contains(candidate.receiver * children.count + candidate.sibling)
			{
				if let property = children[candidate.sibling].property {
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

	/// The lines that bind the payloads of the cases on the routes to the places beneath this scope, which its parent emits
	/// before its builder function, where the parent binds their labels: each field read as the parent's receivers read it.
	nonisolated private var valuesBindingLines: String {
		valuesBindings.map { "\($0.line(readingInstancesOf: callSiteLazilyInstantiatedInstanceProperties))\n" }.joined()
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
	nonisolated private func closedOnFunctionName(builtFor property: Property, enclosingFunctionNames: [BuiltDeclaration: String]) -> String {
		closedOnDeclaration.flatMap { enclosingFunctionNames[$0] } ?? Self.functionName(toBuild: property)
	}

	/// The arguments this scope passes the builder function a lazy cycle closes on, labeled by parameter: the binding of
	/// each label in scope here – a lazily instantiated property's instance where the parameter takes it by value – or
	/// `nil` where it is unavailable.
	nonisolated private func cycleParameterArguments(unavailableProperties: Set<Property>) -> [String] {
		cycleParameters.map { parameter in
			let label = parameter.property.label
			let value = if unavailableProperties.contains(parameter.property) {
				"nil"
			} else if callSiteLazilyInstantiatedInstanceProperties.contains(parameter.property.asUnwrappedProperty) {
				// A deliberate gap: reading the instance here creates it when the function is called, not when a receiver in
				// the function's body first reads it. Mock generation does the same (`mockCycleParameterArguments`). See
				// "Eager instances at a lazy cycle's calls" in `.claude/rules/cycle-generation.md`.
				"\(label).\(Dependency.lazilyInstantiatedInstancePropertyName)"
			} else {
				label
			}
			return "\(label.spelledAsArgumentLabel): \(value)"
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
		enclosingFunctionNames: [BuiltDeclaration: String],
		leadingMemberWhitespace: String,
	) async throws -> [String] {
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
		// them all: the loop's first.
		var valuesBindingLinesByLoop = [Int: String]()
		var valuesBindingMemberIndexByLoop = [Int: Int]()
		if !receivedBuilderLoops.loopByChildIndex.isEmpty {
			let loopByGenerator = Dictionary(
				receivedBuilderLoops.loopByChildIndex.map { (ObjectIdentifier(propertiesToGenerate[$0.key]), $0.value) },
				uniquingKeysWith: { first, _ in first },
			)
			for (index, child) in orderedChildren.enumerated() where !child.generator.isAlias {
				guard let loop = loopByGenerator[ObjectIdentifier(child.generator)] else { continue }
				valuesBindingLinesByLoop[loop, default: ""] += child.generator.valuesBindingLines
				if valuesBindingMemberIndexByLoop[loop] == nil {
					valuesBindingMemberIndexByLoop[loop] = index
				}
			}
			// A `__safeDI_<label>_received` function is named apart, with underscores appended, from every name in scope
			// where it is declared or read (see `namesReceivedFunctionsAvoid`).
			var names = GeneratedNameAllocator(reserving: namesReceivedFunctionsAvoid(
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
				if !child.generator.cycleParameters.isEmpty {
					functionName = names.claim(ReservedName.receivedBuilderFunctionName(of: functionName))
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
		var generatedProperties = [String]()
		var inlinedFills = [String: FillDispatcher.InlinedFill]()
		// What each fill nested by type takes beside its case's payload, then what each dispatcher takes to pass on.
		var fillParametersByKey = [String: [SeamSignature.Hole.Field]]()
		// What the root dispatcher passes of each value it reads from this scope: the caller's declaration, or `nil` where a
		// fill reads it only if available and this scope declares none, or builds it later. A value one fill reads where
		// another reads it too is passed as the fill that finds it available reads it.
		var callerArgumentsByLabel = [String: Set<String>]()
		if !fillDispatchers.isEmpty {
			for child in orderedChildren {
				if let key = child.generator.fillKey, child.generator.fillEmitsCode {
					fillParametersByKey[key] = child.generator.fillParameterFields
					let callerReads = child.generator.fillCallerReads
					for (label, argument) in callerReads.argumentByLabel {
						let forms = callerReads.dependencies.map(\.property).filter { $0.label == label }
						callerArgumentsByLabel[label, default: []].insert(forms.allSatisfy(child.unavailableProperties.contains) ? "nil" : argument)
					}
				}
			}
		}
		let callerArgumentByLabel = callerArgumentsByLabel.compactMapValues { arguments in
			arguments.filter { $0 != "nil" }.min() ?? arguments.min()
		}
		// A seam's caller hands each value on per label (`dispatcherParameters(of:fillReads:)`); a public mock's caller per label
		// and form, per route (`RoutePlan`).
		let dispatcherParametersByKey = FillDispatcher.dispatcherParameters(of: fillDispatchers.filter { !$0.decidesPerRoute }, fillReads: fillParametersByKey)
		let parametersByKey = fillParametersByKey.merging(dispatcherParametersByKey) { fillParameters, _ in fillParameters }
		// A public mock's caller hands each value on per route, and passes a place up on a route that lacks one its fill reads.
		let routePlan = fillDispatchers.contains(where: \.decidesPerRoute) ? FillDispatcher.RoutePlan(of: fillDispatchers, fillParameters: fillParametersByKey) : nil
		let fillsNotInlinable = routePlan?.fillsNotInlinable(of: fillDispatchers) ?? []
		for (index, child) in orderedChildren.enumerated() where child.generator.fillEmitsCode {
			var builderFunctionNames = childBuilderFunctionNames?[index].flatMap(\.self)
				?? BuilderFunctionNames(fillIsSendable: buildsInSendableFunction(ofFill: child.generator))
			if !loopMemberDeclarationsByLoop.isEmpty,
			   let childIndex = propertiesToGenerate.firstIndex(where: { $0 === child.generator }),
			   let loop = receivedBuilderLoops.loopByChildIndex[childIndex]
			{
				builderFunctionNames.loopMemberDeclarations = loopMemberDeclarationsByLoop[loop, default: [:]]
				builderFunctionNames.receivedFunctionName = receivedFunctionNameByIndex[index]
				if !child.generator.isAlias {
					builderFunctionNames.loopValuesBindingLines = valuesBindingMemberIndexByLoop[loop] == index ? valuesBindingLinesByLoop[loop, default: ""] : ""
				}
			}
			let code = try await child.generator.generateCode(
				codeGeneration: codeGeneration,
				unavailableProperties: child.unavailableProperties,
				propertiesGeneratedLater: child.propertiesGeneratedLater,
				builderFunctionNames: builderFunctionNames,
				leadingWhitespace: leadingMemberWhitespace,
			)
			if let key = child.generator.fillKey,
			   inlinableFillKeys.contains(key),
			   !fillsNotInlinable.contains(key),
			   let inlinedFill = Self.inlinedFill(of: child.generator, code: code, leadingMemberWhitespace: leadingMemberWhitespace)
			{
				inlinedFills[key] = inlinedFill
			} else {
				generatedProperties.append(code)
			}
		}
		// A call's dispatchers follow its fills, as a one-level switch over each enum its arguments reach, then the readers of
		// inner seams' levels they read through.
		let readerNameByKey = fillDispatchers.first?.readerNameByKey ?? [:]
		let readers = readerNameByKey.isEmpty ? nil : InnerScopeReaders(enumsByKey: calledBuilders?.enumsByKey ?? [:], nameByKey: readerNameByKey)
		var readerRequests = [InnerScopeReaders.Key]()
		var sendableReaderRequests = Set<InnerScopeReaders.Key>()
		for dispatcher in fillDispatchers {
			let isSendable = sendableFillKeys.contains(dispatcher.key)
			try generatedProperties.append(dispatcher.declaration(
				isSendable: isSendable,
				indent: leadingMemberWhitespace,
				inlinedFills: inlinedFills,
				parametersByKey: parametersByKey,
				callerArgumentByLabel: callerArgumentByLabel,
				routePlan: routePlan,
				typesDeclaredEscaping: typesDeclaredEscaping,
				readers: readers,
			))
			if let readers {
				let requests = dispatcher.readerRequests(parametersByKey: parametersByKey, routePlan: routePlan, readers: readers)
				readerRequests += requests
				if isSendable {
					sendableReaderRequests.formUnion(requests)
				}
			}
		}
		if let readers, !readerRequests.isEmpty {
			generatedProperties += readers.declarations(of: readerRequests, sendableRequests: sendableReaderRequests, indent: leadingMemberWhitespace)
		}
		return generatedProperties
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

	/// `code` with each line indented once more.
	private static func indented(_ code: String) -> String {
		code.split(separator: "\n", omittingEmptySubsequences: false).map { standardIndent + $0 }.joined(separator: "\n")
	}

	/// The arguments a builder function of a type whose `@Forwarded` properties are `forwardedProperties`, in their order,
	/// is passed from `forwardedValue`: the value itself for one property, and its elements by label for several.
	private static func forwardedArguments(of forwardedProperties: [Property], spreading forwardedValue: String) -> [String] {
		let forwardedPropertiesHaveLabels = forwardedProperties.count > 1
		return forwardedProperties.map {
			if forwardedPropertiesHaveLabels {
				"\($0.label.spelledAsArgumentLabel): \(forwardedValue).\($0.label)"
			} else {
				"\($0.label.spelledAsArgumentLabel): \(forwardedValue)"
			}
		}
	}

	/// The declaration of this scope's instantiator, which hands its wrapper the function named `functionName`, called
	/// with `forwardedArguments`: the function itself when it takes no arguments and erases nothing, and otherwise a
	/// closure that calls it. Empty for a scope that builds no instantiator, which no caller asks.
	nonisolated private func instantiatorDeclaration(handing functionName: String, forwardedArguments: String) -> String {
		guard case let .property(instantiable, property, _, _, _, _) = scopeData else { return "" }
		let typeDescription = property.typeDescription.asSource
		// A type constructed by annotation spells its generic arguments only in `propertyDeclaration`.
		let unwrappedTypeDescription = property
			.typeDescription
			.unwrapped
			.spelledForConstruction
		let propertyDeclaration = if !instantiable.declarationType.isExtension, typeDescription == unwrappedTypeDescription {
			"let \(property.label)"
		} else {
			"let \(property.asSource)"
		}
		return "\(propertyDeclaration) = \(instantiatorExpression(handing: functionName, forwardedArguments: forwardedArguments))"
	}

	/// The wrapper `instantiatorDeclaration(handing:forwardedArguments:)` declares.
	nonisolated private func instantiatorExpression(handing functionName: String, forwardedArguments: String) -> String {
		guard case let .property(_, property, _, erasedToConcreteExistential, _, _) = scopeData else { return "" }
		let unwrappedTypeDescription = property
			.typeDescription
			.unwrapped
			.spelledForConstruction
		let instantiatedTypeDescription = property
			.typeDescription
			.unwrapped
			.asInstantiatedType
			.asSource
		return if forwardedArguments.isEmpty, !erasedToConcreteExistential {
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
		case let .root(instantiable, seamRoot):
			switch codeGeneration {
			case .dependencyTree:
				if let seamRoot {
					return try await generateSeamRootCode(
						instantiable: instantiable,
						seamRoot: seamRoot,
						unavailableProperties: unavailableProperties,
						propertiesGeneratedLater: propertiesGeneratedLater,
						builderFunctionNames: builderFunctionNames,
					)
				}
				let argumentList = try instantiable.generateArgumentList()
				if instantiable.dependencies.isEmpty {
					return ""
				} else {
					// Attributes precede the initializer's modifiers on its line, as `mockAttributes` precede a mock's.
					let attributesPrefix = instantiable.generatedInitializerAttributes.isEmpty ? "" : "\(instantiable.generatedInitializerAttributes) "
					return try await """
					extension \(instantiable.concreteInstantiable.asSource) {
					    \(attributesPrefix)public \(instantiable.declarationType == .classType ? "convenience " : "")init() {
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
			seamCall,
		):
			// A type built with its hand-written mock, as one built with its initializer, is constructed inside its builder
			// function, whose own parameters hide the declarations of their labels where it is called.
			let argumentList = if publicMockCall != nil, let mockInitializer = instantiable.mockInitializer {
				// A call of another module's public mock in a fill a mock declares, which passes each parameter of the tier
				// in signature order, a builder it fills among them, and no `safeDIOverrides`: no override reaches a fill. A
				// by-value parameter whose label the tree holds as a lazily instantiated property is passed its instance, as
				// a call outside a fill is (`dependencyArgument`).
				mockInitializer.arguments.map { argument in
					let value = holeArgumentValuesByLabel[argument.innerLabel] ?? instantiable.dependencies.first(where: { $0.property.label == argument.innerLabel }).map { dependency in
						if unavailableProperties.contains(dependency.property) {
							"nil"
						} else if dependency.source.isReceived, lazilyInstantiatedInstanceProperties.contains(dependency.property.asUnwrappedProperty) {
							"\(argument.innerLabel).\(Dependency.lazilyInstantiatedInstancePropertyName)"
						} else {
							argument.innerLabel
						}
					} ?? argument.innerLabel
					return "\(argument.label.spelledAsArgumentLabel): \(value)"
				}.joined(separator: ", ")
			} else if constructsWithHandWrittenMock, let mockInitializer = instantiable.mockInitializer {
				// A type a fill builds with its hand-written mock is passed what the mock takes of its dependencies, as an
				// initializer is; each other parameter of the mock keeps its default.
				try mockInitializer.createInitializerArgumentList(
					given: instantiable.dependencies,
					unavailableProperties: bodyUnavailableProperties(unavailableProperties),
					lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties,
				)
			} else {
				try instantiable.generateArgumentList(
					unavailableProperties: bodyUnavailableProperties(unavailableProperties),
					lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties,
				)
			}
			let concreteTypeName = instantiable.concreteInstantiable.asSource
			let instantiationDeclaration = if publicMockCall != nil {
				"\(concreteTypeName).\(InstantiableVisitor.mockMethodName)"
			} else if constructsWithHandWrittenMock {
				"\(concreteTypeName).\(instantiable.customMockName ?? InstantiableVisitor.mockMethodName)"
			} else if instantiable.declarationType.isExtension {
				"\(concreteTypeName).\(InstantiableVisitor.instantiateMethodName)"
			} else {
				concreteTypeName
			}
			// A seam call passes a builder for each of the seam's holes after the tier's parameters; a call of a public
			// mock passes them among its arguments.
			let holeArgumentList = publicMockCall == nil
				? builderCallArguments.map { "\($0.label): \($0.value)" }
				: []
			let returnLineSansReturn = holeArgumentList.isEmpty
				? "\(instantiationDeclaration)(\(argumentList))"
				: "\(instantiationDeclaration)(\(([argumentList].filter { !$0.isEmpty } + holeArgumentList).joined(separator: ", ")))"
			// The payloads of the cases on the routes to the places beneath this scope, bound before its builder function, where
			// the scope's parent binds its labels: each field read as the parent's receivers read it.
			let valuesBindingLines = builderFunctionNames.loopValuesBindingLines ?? valuesBindingLines
			// What ends the line that constructs the type, after the construction.
			let constructionLineEnd = builtInlineSeamComment.map { " \($0)" } ?? ""
			// A call to a seam's generated initializer refers to the enum the seam's module generated for the
			// signature the call was generated from, on the line before the call, so a call generated from another
			// signature fails to compile here rather than pass `nil` where the initializer expects a value. The
			// statement is emitted as the body's only generated property, so the call is made in a builder function.
			let seamGuardLines: [String] = if let seamCall {
				["\(Self.standardIndent)_ = \(concreteTypeName).\(seamCall.guardTypeName).self\(seamCall.comment.lineEnd(for: instantiable.concreteInstantiable))"]
			} else {
				[]
			}

			let propertyType = property.propertyType
			switch propertyType {
			case .instantiator,
			     .erasedInstantiator,
			     .sendableInstantiator,
			     .sendableErasedInstantiator:
				let forwardedProperties = forwardedProperties.sorted()
				// The wrapper's closure spreads its argument; a fill, which leaves the wrapper to the seam, spreads its parameter.
				let forwardedValue = isBuiltByFill ? Self.forwardedValueParameterName(forBuilding: property) : "$0"
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
									+ cycleParameters.map { "\($0.property.label.spelledAsArgumentLabel): \($0.property.label)" },
							).joined(separator: ", "),
						))
					} else {
						builderFunctionNames.loopMemberDeclarations[reboundProperty].map(Self.indented)
					}
				}
				let generatedProperties = try await rebindingLines + seamGuardLines + generateProperties(
					codeGeneration: codeGeneration,
					propertiesGeneratedLater: bodyPropertiesGeneratedLater(propertiesGeneratedLater),
					enclosingFunctionNames: builderFunctionNames.enclosingFunctionNames,
					leadingMemberWhitespace: Self.standardIndent,
				)
				// The function a lazy cycle closes on also takes the parameters its cycle-closing scopes pass.
				let functionParameters = forwardedProperties + (isPropertyCycle ? [] : cycleParameters.map(\.property))
				let functionArguments = if functionParameters.isEmpty {
					""
				} else {
					functionParameters.initializerFunctionParameters(amongTypesDeclaredEscaping: typesDeclaredEscaping).map(\.description).joined()
				}
				let functionDecorator = if buildsInSendableFunction {
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
					\(Self.standardIndent)\(generatedProperties.isEmpty ? "" : "return ")\(returnLineSansReturn)\(constructionLineEnd)
					}

					"""
				}

				guard !isBuiltByFill else {
					let builderCall = "\(functionName)(\(forwardedArguments))"
					return "\(valuesBindingLines)\(functionDeclaration)return \(erasedToConcreteExistential ? "\(property.typeDescription.unwrapped.asInstantiatedType.asSource)(\(builderCall))" : builderCall)"
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
							return "\(parameter.property.label.spelledAsArgumentLabel): \(parameter.property.label)"
						} else {
							return argument
						}
					}
					let receivedFunctionParameters = forwardedProperties.isEmpty
						? ""
						: forwardedProperties.initializerFunctionParameters(amongTypesDeclaredEscaping: typesDeclaredEscaping).map(\.description).joined()
					let callArguments = (forwardedProperties.map { "\($0.label.spelledAsArgumentLabel): \($0.label)" } + cycleArguments).joined(separator: ", ")
					let receivedFunctionDecorator = buildsInSendableFunction || property.propertyType.isSendable ? "@Sendable " : ""
					let receivedFunctionDeclaration = """
					\(receivedFunctionDecorator)func \(receivedFunctionName)(\(receivedFunctionParameters)) -> \(concreteTypeName) {
					\((memberLines + ["\(Self.standardIndent)\(memberLines.isEmpty ? "" : "return ")\(functionName)(\(callArguments))"]).joined(separator: "\n"))
					}

					"""
					return """
					\(valuesBindingLines)\(functionDeclaration)\(receivedFunctionDeclaration)\(instantiatorDeclaration(
						handing: receivedFunctionName,
						forwardedArguments: Self.forwardedArguments(of: forwardedProperties, spreading: forwardedValue).joined(separator: ", "),
					))
					"""
				}
				return """
				\(valuesBindingLines)\(functionDeclaration)\(instantiatorDeclaration(handing: functionName, forwardedArguments: forwardedArguments))
				"""
			case .lazilyInstantiated,
			     .sendableLazilyInstantiated:
				// The builder function is the one a constant with children declares. A constant calls it
				// immediately; a lazily instantiated property hands it to its wrapper, which calls it the
				// first time the instance is requested. Dependency cycle validation treats the property
				// as a constant, so it is never the deferred hop of a cycle. A scope that closes a cycle
				// declares no function: it hands its wrapper the function of the declaration it repeats,
				// with that function's cycle parameters, as an instantiator that closes a cycle does. The
				// wrapper is always spelled with its generic argument, so the declaration needs no type
				// annotation: an optional property receives the wrapper through optional promotion.
				let unwrappedTypeDescription = property
					.typeDescription
					.unwrapped
					.asSource
				let cycleArguments = cycleParameterArguments(unavailableProperties: unavailableProperties).joined(separator: ", ")
				let functionName = if isPropertyCycle {
					closedOnFunctionName(builtFor: property, enclosingFunctionNames: builderFunctionNames.enclosingFunctionNames)
				} else {
					builderFunctionNames.functionName ?? Self.functionName(toBuild: property)
				}
				let lazilyInstantiatedInstantiation = if erasedToConcreteExistential {
					"""
					\(unwrappedTypeDescription) {
					\(Self.standardIndent)\(property.typeDescription.asInstantiatedType.asSource)(\(functionName)(\(cycleArguments)))
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
				guard !isPropertyCycle else {
					return "\(valuesBindingLines)let \(property.label) = \(lazilyInstantiatedInstantiation)"
				}
				let generatedProperties = try await seamGuardLines + generateProperties(
					codeGeneration: codeGeneration,
					propertiesGeneratedLater: bodyPropertiesGeneratedLater(propertiesGeneratedLater),
					enclosingFunctionNames: builderFunctionNames.enclosingFunctionNames,
					leadingMemberWhitespace: Self.standardIndent,
				)
				let functionDecorator = if buildsInSendableFunction {
					"@Sendable "
				} else {
					""
				}
				// The function a cycle closes on also takes the parameters its cycle-closing scopes pass.
				let functionParameters = cycleParameters.map(\.property)
				let functionArguments = functionParameters.isEmpty ? "" : functionParameters.initializerFunctionParameters(amongTypesDeclaredEscaping: typesDeclaredEscaping).map(\.description).joined()
				let builderCall = "\(functionName)(\(cycleArguments))"
				let lastLine = if isBuiltByFill {
					"return \(erasedToConcreteExistential ? "\(property.typeDescription.asInstantiatedType.asSource)(\(builderCall))" : builderCall)"
				} else {
					"let \(property.label) = \(lazilyInstantiatedInstantiation)"
				}

				return """
				\(valuesBindingLines)\(functionDecorator)func \(functionName)(\(functionArguments)) -> \(concreteTypeName) {
				\(generatedProperties.joined(separator: "\n"))
				\(Self.standardIndent)\(generatedProperties.isEmpty ? "" : "return ")\(returnLineSansReturn)\(constructionLineEnd)
				}
				\(lastLine)
				"""
			case .constant:
				let callArguments = cycleParameterArguments(unavailableProperties: unavailableProperties).joined(separator: ", ")
				guard !isPropertyCycle else {
					// A scope that closes a cycle declares no function: it calls the function of the declaration it repeats
					// with that function's cycle parameters, typed as a constant with content is. A closer builds nothing, so
					// it holds no seam's site and `valuesBindingLines` is empty, as it is for every closer.
					let call = "\(closedOnFunctionName(builtFor: property, enclosingFunctionNames: builderFunctionNames.enclosingFunctionNames))(\(callArguments))"
					return if erasedToConcreteExistential {
						"\(valuesBindingLines)let \(property.label) = \(property.typeDescription.asSource)(\(call))\n"
					} else {
						"\(valuesBindingLines)let \(property.asSource) = \(call)\n"
					}
				}
				let generatedProperties = try await seamGuardLines + generateProperties(
					codeGeneration: codeGeneration,
					propertiesGeneratedLater: bodyPropertiesGeneratedLater(propertiesGeneratedLater),
					enclosingFunctionNames: builderFunctionNames.enclosingFunctionNames,
					leadingMemberWhitespace: Self.standardIndent,
				)
				let functionDecorator = if buildsInSendableFunction {
					"@Sendable "
				} else {
					""
				}
				// The function a cycle closes on also takes the parameters its cycle-closing scopes pass.
				let functionParameters = cycleParameters.map(\.property)
				let functionArguments = functionParameters.isEmpty ? "" : functionParameters.initializerFunctionParameters(amongTypesDeclaredEscaping: typesDeclaredEscaping).map(\.description).joined()

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
					\(functionDecorator)func \(functionName)(\(functionArguments)) -> \(concreteTypeName) {
					\(nonEmptyGeneratedProperties.joined(separator: "\n"))
					\(Self.standardIndent)return \(returnLineSansReturn)\(constructionLineEnd)
					}

					"""
				}
				let existentialWrappedReturn = if erasedToConcreteExistential {
					"\(property.typeDescription.asSource)(\(returnLineSansReturn))"
				} else {
					returnLineSansReturn
				}
				let initializer = if !hasGeneratedContent {
					existentialWrappedReturn + constructionLineEnd
				} else if erasedToConcreteExistential {
					"\(property.typeDescription.asSource)(\(functionName)(\(callArguments)))"
				} else {
					"\(functionName)(\(callArguments))"
				}

				// The payloads a seam's tree binds before building a scope that leads to a place.
				return "\(valuesBindingLines)\(functionDeclaration)\(propertyDeclaration) = \(initializer)\n"
			}
		case let .hole(property, _, site):
			// A tree built only to compute the seam's signature has no site, and generates nothing.
			guard let site else { return "" }
			return Self.buildSiteCode(of: property, at: site, functionName: builderFunctionNames.functionName, readingInstancesOf: callSiteLazilyInstantiatedInstanceProperties)
		case let .fill(hole, functionName):
			return try await generateFillCode(
				of: hole,
				functionName: functionName,
				isSendable: builderFunctionNames.fillIsSendable,
				codeGeneration: codeGeneration,
				propertiesGeneratedLater: propertiesGeneratedLater,
				enclosingFunctionNames: builderFunctionNames.enclosingFunctionNames,
			)
		case let .alias(property, fulfillingProperty, erasedToConcreteExistential, onlyIfAvailable, declarationReference):
			if Self.aliasIsBoundToNil(onlyIfAvailable: onlyIfAvailable, fulfillingProperty: fulfillingProperty, unavailableProperties: unavailableProperties) {
				// An `onlyIfAvailable` alias whose fulfilling property is unavailable is still declared, so that its declaring
				// type and everything beneath it read it, `nil` included, rather than a declaration of its label further up.
				return Self.referencingDeclaration(of: "let \(property.asSource) = nil", by: declarationReference)
			} else {
				// The alias is bound from the declared property it reads, which may be `nil` where it is an optional
				// property – a seam's optional parameter, a parameter made optional, or the optional form of the fulfilling
				// property – and is otherwise a non-optional value. A wrapper's instance is read from a non-optional wrapper.
				return Self.referencingDeclaration(
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
	}

	private static func structDeclaration(named name: String, fields: [SeamSignature.Hole.Field], indent: String, typesDeclaredEscaping: Set<TypeDescription>) -> String {
		guard !fields.isEmpty else { return "\(indent)public struct \(name) {}" }
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
			return (["\(indent)public struct \(name) {"] + fieldDeclarations + ["\(indent)}"]).joined(separator: "\n")
		}
		let memoDeclarations = memoFields.compactMap { field in
			field.memoType.map { "\(memberIndent)let \(field.memoName): \($0.asSource)" }
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
		var lines = ["\(indent)public struct \(name) {"]
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
		return scopeEnums.filter { $0.rootTypeName == nil && $0.key.seamType == ownType }.map { scopeEnum in
			let key = scopeEnum.key
			// An enum nested by type holds the enums of the types it leads to, which are declared inside it; a case can hold an
			// enum of the other family, which it spells from that family's root.
			let enumsOfHoleType = scopeEnums.filter { $0.key.describedType != nil && $0.key.seamType == key.seamType && $0.key.holeType == key.holeType }
			let nestedEnums = enumsOfHoleType.filter { $0.key.isSendable == key.isSendable }
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
			let declaration = scopeEnumDeclaration(of: scopeEnum, nestedEnums: nestedEnums, enumsOfHoleType: enumsOfHoleType, holesBySite: holesBySite, typesDeclaredEscaping: typesDeclaredEscaping)
			guard let marker = unreadTypeComment?.markerLine(namedBy: namedTypes, indent: standardIndent) else { return declaration }
			return "\(marker)\n\(declaration)"
		}
	}

	/// The declaration of `scopeEnum`, nested in the seam: its cases in the order the seam's generated code first reaches them,
	/// then each case's payload struct, then, for a root enum nested by type, each of `nestedEnums`. `@frozen public`, so a
	/// caller can switch over it without a default in any module, and so its access is the seam's. A case that holds an enum
	/// nested by type spells it from its root, found among `enumsOfHoleType`.
	static func scopeEnumDeclaration(of scopeEnum: SeamSignature.ScopeEnum, nestedEnums: [SeamSignature.ScopeEnum] = [], enumsOfHoleType: [SeamSignature.ScopeEnum] = [], holesBySite: [SeamSignature.Hole.Site: SeamSignature.Hole], typesDeclaredEscaping: Set<TypeDescription>, indent: String = standardIndent) -> String {
		let caseIndent = indent + standardIndent
		var caseLines = [String]()
		var payloadStructs = [String]()
		// A case's payload escapes, so a function type needs no `@escaping`, which a case cannot spell. A function type with an
		// isolation specifier is given an unlabeled name: a case's parameter list reads an unnamed specifier as a parameter's
		// own.
		func forwardedPayload(of hole: SeamSignature.Hole?) -> String? {
			hole?.forwardedType.map { forwardedType in
				let payload = forwardedType.strippingEscaping.asSource
				return payload.hasPrefix("nonisolated(") ? "_ forwarded: \(payload)" : payload
			}
		}
		/// A case's declaration of `payloads`, the values it carries, none of which may be missing but the forwarded value.
		func caseLine(_ name: String, isIndirect: Bool = false, payloads: [String?]) -> String {
			let carried = payloads.compactMap(\.self)
			return "\(caseIndent)\(isIndirect ? "indirect " : "")case \(name)\(carried.isEmpty ? "" : "(\(carried.joined(separator: ", ")))")"
		}
		for enumCase in scopeEnum.cases {
			let valuesTypeName = enumCase.values?.typeName
			if let values = enumCase.values {
				payloadStructs.append(structDeclaration(named: values.typeName, fields: values.fields, indent: caseIndent, typesDeclaredEscaping: typesDeclaredEscaping))
			}
			switch enumCase.kind {
			case let .place(sites):
				caseLines.append(caseLine(enumCase.name, payloads: [valuesTypeName, forwardedPayload(of: sites.first.flatMap { holesBySite[$0] })]))
			case let .nested(enumKey, isIndirect):
				let nestedType = enumsOfHoleType.first { $0.key == enumKey }?.typeQualified(by: nil).asSource ?? ""
				caseLines.append(caseLine(enumCase.name, isIndirect: isIndirect, payloads: [valuesTypeName, nestedType]))
			case let .inner(_, enumType, isIndirect):
				caseLines.append(caseLine(enumCase.name, isIndirect: isIndirect, payloads: [valuesTypeName, enumType.asSource]))
			case let .fill(_, innerEnumType, enumKey, isIndirect):
				let nestedType = enumsOfHoleType.first { $0.key == enumKey }?.typeQualified(by: nil).asSource ?? ""
				caseLines.append(caseLine(enumCase.name, isIndirect: isIndirect, payloads: [valuesTypeName, innerEnumType?.asSource, nestedType]))
			}
		}
		var body = caseLines.joined(separator: "\n")
		if !payloadStructs.isEmpty {
			body += (body.isEmpty ? "" : "\n\n") + payloadStructs.joined(separator: "\n\n")
		}
		// Only the root declares the enums nested in it; a nested enum's cases spell them from the root.
		if scopeEnum.rootTypeName == nil {
			for nestedEnum in nestedEnums {
				body += (body.isEmpty ? "" : "\n\n") + scopeEnumDeclaration(of: nestedEnum, enumsOfHoleType: enumsOfHoleType, holesBySite: holesBySite, typesDeclaredEscaping: typesDeclaredEscaping, indent: caseIndent)
			}
		}
		return """
		\(indent)@frozen public enum \(scopeEnum.typeName) {
		\(body)
		\(indent)}
		"""
	}

	/// The code a seam's tree generates at a site of `property`, a hole: its builder called with the case of its enum that
	/// carries the values in scope there. A constant is bound with its declared type, as inline binds an existential. A
	/// wrapper that forwards a value is built around a closure that makes the call, handing it `$0`, which no parameter of a
	/// function declared here could take when it is a function type. Any other wrapper is built around a function that makes
	/// the call, as inline builds a wrapper around its builder function, which is `@Sendable` for a `Sendable` wrapper.
	/// - Parameters:
	///   - functionName: The name of that function where it differs from `functionName(toBuild:)`.
	///   - lazilyInstantiatedInstanceProperties: The by-value properties whose labels the site's owner holds only as a
	///     `LazilyInstantiated` property, whose instance the payload reads, as the owner's receivers do
	///     (`SeamHoles.valuesArguments(of:readingInstancesOf:)`).
	static func buildSiteCode(of property: Property, at site: SeamSignature.Hole, functionName: String?, readingInstancesOf lazilyInstantiatedInstanceProperties: Set<Property> = []) -> String {
		// A place nested by type is handed what its owner binds before it; the cases that lead to it carry what each type on
		// the way binds, which the tree bound before building the next. A place in a `@Sendable` enum held in a `Sendable`
		// wrapper carries nothing.
		let fields = site.enumPlace?.values ?? site.fields
		let arguments = SeamHoles.valuesArguments(of: fields, readingInstancesOf: lazilyInstantiatedInstanceProperties)
		let valuesArgument = site.valuesType(qualifiedBy: nil).map { "\($0.asSource)(\(arguments))" }
		// The expression that builds the value, the value an instantiator forwards being `forwarded`: the case carries it
		// after its values.
		func buildExpression(forwarding forwarded: String?) -> String {
			let payload = [valuesArgument, forwarded].compactMap(\.self).joined(separator: ", ")
			let ownCase = payload.isEmpty ? ".\(site.enumPlace?.caseName ?? "")" : ".\(site.enumPlace?.caseName ?? "")(\(payload))"
			let value = (site.enumPlace?.route ?? []).reversed().reduce(ownCase) { wrapped, step in
				".\(step.caseName)(\(step.leadingArguments)\(wrapped))"
			}
			return "\(site.internalName)(\(value))"
		}
		let propertyType = property.propertyType
		guard !propertyType.isConstant else {
			return "let \(property.asSource) = \(buildExpression(forwarding: nil))"
		}
		let unwrappedType = property.typeDescription.unwrapped
		// A type constructed by annotation spells its generic arguments only in the declaration's annotation.
		let declaration = property.typeDescription.asSource == unwrappedType.spelledForConstruction ? "let \(property.label)" : "let \(property.asSource)"
		guard !propertyType.forwardsPropertiesOfBuiltType, site.forwardedType == nil else {
			// The wrapper's closure takes the forwarded value – `T.ForwardedProperties`, or an erased instantiator's first
			// generic argument – escaping when it is a function type, as no parameter of a function declared here could, since
			// the seam cannot tell whether it is one: a typealias spells a function type as a name.
			return """
			\(declaration) = \(unwrappedType.spelledForConstruction) {
			\(standardIndent)\(buildExpression(forwarding: "$0"))
			}
			"""
		}
		let functionName = functionName ?? site.wrapperFunctionName ?? Self.functionName(toBuild: property)
		return """
		\(propertyType.isSendable ? "@Sendable " : "")func \(functionName)() -> \(site.builtType.asSource) {
		\(standardIndent)\(buildExpression(forwarding: nil))
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
		codeGeneration: CodeGeneration,
		propertiesGeneratedLater: Set<Property>,
		enclosingFunctionNames: [BuiltDeclaration: String],
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
		)
		// One function its fulfiller forwards is the forwarded value itself, which escapes into what the fill builds, so
		// the value's type is a function type however it is spelled: for `Instantiator<T>`, `T.ForwardedProperties`. A
		// function spelled as a name is one the fulfiller's subtree declares `@escaping` (`typesDeclaredEscaping`).
		let fulfillerForwardedDependencies = (child.builtInstantiable?.dependencies ?? []).filter { $0.source == .forwarded }
		let fulfillerForwardsOneFunction = fulfillerForwardedDependencies.count == 1 && (
			fulfillerForwardedDependencies[0].property.typeDescription.isClosure
				|| child.typesDeclaredEscaping.contains(fulfillerForwardedDependencies[0].property.typeDescription)
		)
		var body = childCode.joined(separator: "\n").split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
		// A wrapper's scope returns what its builder function builds, and a constant's has bound it.
		if property.propertyType.isConstant {
			body.append(indent + "return \(property.label)")
		}
		// A fill of a place nested by type binds what its case's payload holds, and takes what a type further out binds.
		let nestedByTypeValues = hole.enumPlace?.values
		let valuesType = hole.valuesType(qualifiedBy: hole.scopeSeamType)
		let bindings = valuesType == nil ? [] : (nestedByTypeValues ?? hole.fields).filter(isRead).map { "\(indent)let \($0.property.label) = \(scopeParameterName).\($0.property.label.spelledAsMemberReference)" }
		var parameters = valuesType.map { ["_ \(scopeParameterName): \($0.asSource)"] } ?? []
		if let forwardedType = hole.forwardedType {
			let parameterType = fulfillerForwardsOneFunction && !forwardedType.isClosure
				? TypeDescription.attributed(forwardedType, specifiers: [], attributes: ["escaping"])
				: forwardedType
			parameters.append("_ \(Self.forwardedValueParameterName(forBuilding: property)): \(parameterType.asSource)")
		}
		parameters += fillParameterFields.map { "\($0.property.label.spelledAsArgumentLabel): \($0.property.typeDescription.asFunctionParameter(amongTypesDeclaredEscaping: typesDeclaredEscaping).asSource)" }
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
			signature.builders.map { "\($0.label(inTierAt: tier).spelledAsArgumentLabel): \($0.parameterType.asSource)" }
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
				generics: [parameter.deferredValueType],
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
				)
				let argumentList = try instantiable.generateArgumentList(
					unavailableProperties: unavailableProperties,
				)
				body = (memoLines + generatedProperties + ["\(bodyIndent)self.init(\(argumentList))"]).joined(separator: "\n")
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
				\(Self.standardIndent)/// To call this type from code you write, set `\(SafeDIConfigurationVisitor.generatePlainDependencyTreeInitializersArgumentLabel): true` in this module's `#\(SafeDIConfigurationVisitor.macroName)`.
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
				let forwardedArguments = parameters.map { "\($0.generatedOnlyArgumentLabel): \($0.property.label)" }
					+ signature.builders.map { "\($0.generatedOnlyArgumentLabel(inTierAt: tier)): \($0.label(inTierAt: tier))" }
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
		return """
		extension \(typeName) {
		\((scopeTypes + initializers).joined(separator: "\n\n"))
		}

		extension \(typeName) {
		    public enum \(signature.guardTypeName) {}
		}
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
		/// The `@Instantiated` dependencies, of the mocked type and of the types in its tree, that no node builds.
		let flatUncoveredParameters: [UncoveredParameter]
		/// The lazily instantiated dependencies the tree receives and the mock cannot build.
		let lazilyInstantiatedReceivedProperties: [Property]
		/// The `LazilyInstantiated`, among `lazilyInstantiatedReceivedProperties`, that each entry of
		/// `flatReceivedProperties` or `onlyIfAvailableReceivedProperties` is the instance of, for the entries whose label
		/// and type a forwarded property of the mocked type has. Such an entry is named after its `LazilyInstantiated`,
		/// and no receive of the forwarded property is passed it.
		let lazilyInstantiatedPropertyByInstanceBesideForwardedProperty: [Property: Property]
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
	struct SendableAutoclosureParameter {
		/// The parameter's name, `UncoveredParameter.label`.
		let name: String
		/// The name of the local the body reads the closure into before any builder function, so that the binding
		/// of the value under `name` in a scope that instantiates the dependency can call the closure however the
		/// scopes around it bind `name`: `__safeDI_<name>`. The prefix keeps it out of the labels SafeDI is given, and
		/// no builder function in scope has the name, since `name` is apart from every binding in the mock.
		let localName: String
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
		let otherFlatLabels = parameters.forwardedDependencies.map(\.property.label)
			+ parameters.rootDefaultParameters.map(\.label)
			+ uncoveredDependencyNames
			+ parameters.onlyIfAvailableReceivedProperties.map(\.label)
		// Map of (label → (type → disambiguatedLabel)) for flat received
		// parameters whose label collided with another flat parameter. Builder calls
		// for child nodes that would reference the original label must substitute
		// the disambiguated name so the generated code references a real binding.
		// A builder the tree passes up from a call of another module's public mock is read by the leaf that makes the call,
		// wherever it is in the tree, so its parameter is named apart from every label a scope enclosing the leaf declares,
		// which would hide it there.
		let passedUpBuilders = Self.passedUpBuilders(in: treePropertyNodes)
		let preferredNames = parameters.flatReceivedProperties.map(\.label)
		let namesInScope = Set(otherFlatLabels).union(treeBindingNames)
		// The instance of a `LazilyInstantiated` beside a forwarded property is named after
		// its `LazilyInstantiated`, and is only ever read by the wrapper bound below, so a
		// receive of the forwarded property is not passed it.
		var flatReceivedNames = Self.namesApart(
			preferredNames: preferredNames,
			typeDescriptions: parameters.flatReceivedProperties.map { property in
				parameters.lazilyInstantiatedPropertyByInstanceBesideForwardedProperty[property]?.typeDescription ?? property.typeDescription
			},
			namesInScope: namesInScope,
			reservedNames: namesDeclaredInBuilderFunctions,
			hiddenEntries: Set(parameters.flatReceivedProperties.indices.filter { passedUpBuilders.hidden.contains(parameters.flatReceivedProperties[$0]) }),
		)
		// A passed-up builder named apart is named after the type whose mock it is passed to (`serviceBuilder_Panel`),
		// unless that name is taken or two such builders would share it: then it keeps the name above.
		let renamedPassedUpBuilderIndices = parameters.flatReceivedProperties.indices.filter { index in
			passedUpBuilders.calledTypeByProperty[parameters.flatReceivedProperties[index]] != nil && flatReceivedNames[index] != preferredNames[index]
		}
		if !renamedPassedUpBuilderIndices.isEmpty {
			let calledStemNames = renamedPassedUpBuilderIndices.compactMap { index -> (index: Int, name: String)? in
				let property = parameters.flatReceivedProperties[index]
				return passedUpBuilders.calledTypeByProperty[property].map { calledType in
					(index, "\(property.label)_\(DependencyTreeGenerator.seamStem(of: calledType))".spelledAsIdentifier)
				}
			}
			// Each name is decided on its own, against names none of these choices changes, so the order decides nothing.
			let takenNames = namesInScope
				.union(namesDeclaredInBuilderFunctions)
				.union(preferredNames)
				.union(flatReceivedNames)
			var calledStemNameCounts = [String: Int]()
			for calledStemName in calledStemNames {
				calledStemNameCounts[calledStemName.name, default: 0] += 1
			}
			for calledStemName in calledStemNames where calledStemNameCounts[calledStemName.name] == 1 && !takenNames.contains(calledStemName.name) {
				flatReceivedNames[calledStemName.index] = calledStemName.name
			}
		}
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
		let receivedProperties = receivedProperties.subtracting(receivedOnlyByPublicMockCallsLeftOut)
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
		let dependencyLabels = Set(instantiable.dependencies.map(\.property.label))
		var rootDefaultParameters = [MockRootParameters.RootDefaultParameter]()
		// The parameters of `mock()` that keep their labels, which a binding of the root's tree would hide: the
		// forwarded parameters, which are passed on under their labels, and the default-valued ones, whose labels
		// are those of the construction initializer.
		var parametersKeepingTheirLabels = forwardedDependencies.map(\.property)
		if let rootConstructionInitializer {
			for argument in rootConstructionInitializer.arguments {
				guard argument.hasDefaultValue,
				      !dependencyLabels.contains(argument.innerLabel),
				      argument.label != "_",
				      let defaultExpression = argument.defaultValueExpression
				else { continue }
				rootDefaultParameters.append(MockRootParameters.RootDefaultParameter(
					label: argument.label,
					typeSource: argument.typeDescription.asFunctionParameter.asSource,
					defaultExpression: defaultExpression,
					typeDescription: argument.typeDescription.strippingEscaping,
				))
				parametersKeepingTheirLabels.append(Property(label: argument.label, typeDescription: argument.typeDescription))
			}
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
			receivedParameterProperties = Set(
				receivedProperties.lazy
					.filter { !isFulfilledByForwardedProperty($0) || isBesideForwardedProperty($0) }
					.map(\.asValidatedForDependencyCycles),
			)
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
		let flatUncoveredParameters = uncoveredDependencies.properties.indices.map { index in
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
			lazilyInstantiatedReceivedProperties: lazilyInstantiatedReceivedProperties,
			lazilyInstantiatedPropertyByInstanceBesideForwardedProperty: lazilyInstantiatedPropertyByInstanceBesideForwardedProperty,
			receivedOnlyByPublicMockCallsLeftOut: receivedOnlyByPublicMockCallsLeftOut,
			typesDeclaredEscaping: typesDeclaredEscaping,
			mockBuilders: mockBuilders,
		)
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
		// cannot be downcast implicitly. Use `mockReturnType` for those cases,
		// and fall back to `typeName` when there is no custom mock or the custom
		// mock already returns the concrete type / `Self`.
		let mockMethodReturnType: String = {
			guard let mockReturnType = instantiable.mockReturnType,
			      !instantiable.mockReturnTypeIsCompatible(withPropertyType: instantiable.concreteInstantiable)
			else { return typeName }
			return mockReturnType.asSource
		}()

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
		let lazilyInstantiatedReceivedProperties = parameters.lazilyInstantiatedReceivedProperties
		let lazilyInstantiatedPropertyByInstanceBesideForwardedProperty = parameters.lazilyInstantiatedPropertyByInstanceBesideForwardedProperty

		// The names `mockRootParameters` named the uncovered dependencies apart from, which the rest of the mock
		// is named apart from too.
		let parameterNames = Self.mockRootParameterNames(of: parameters)
		let namesDeclaredInBuilderFunctions = parameterNames.namesDeclaredInBuilderFunctions
		let rootLabelMap = parameters.rootLabelMap
		let treeBindingNames = parameterNames.treeBindingNames
		let uncoveredDependencyNames = flatUncoveredParameters.map(\.label)
		var uncoveredDependencyNameMap = [String: [TypeDescription: String]]()
		for uncoveredParameter in flatUncoveredParameters where uncoveredParameter.label != uncoveredParameter.property.label {
			uncoveredDependencyNameMap[uncoveredParameter.property.label, default: [:]][uncoveredParameter.property.typeDescription] = uncoveredParameter.label
		}
		let allFlatLabels = parameterNames.otherFlatLabels + flatReceivedProperties.map(\.label)
		let flatReceivedNames = parameterNames.flatReceivedNames
		var flatParameterDisambiguationMap = [String: [TypeDescription: String]]()
		for (property, name) in zip(flatReceivedProperties, flatReceivedNames)
			where name != property.label && lazilyInstantiatedPropertyByInstanceBesideForwardedProperty[property] == nil
		{
			flatParameterDisambiguationMap[property.label, default: [:]][property.typeDescription] = name
		}
		// safedi-source-rule: allow uniqueKeysWithValues — the keys are the elements of a set, `receivedParameterProperties`.
		let flatReceivedNameByProperty = Dictionary(uniqueKeysWithValues: zip(flatReceivedProperties, flatReceivedNames))
		// A builder the tree passes up that a `@Sendable` builder function captures is taken `@Sendable`.
		let sendablePassedUpBuilders = parameters.parameterTree.passedUpBuildersCapturedBySendableFunctions
		let flatReceivedParameters = zip(flatReceivedProperties, flatReceivedNames).map { property, name in
			let typeDescription = if sendablePassedUpBuilders.contains(property), !property.typeDescription.isSendableFunction {
				property.typeDescription.asSendableFunction
			} else {
				property.typeDescription
			}
			return (
				label: name,
				typeSource: typeDescription.asFunctionParameter(amongTypesDeclaredEscaping: parameters.typesDeclaredEscaping).asSource,
			)
		}
		let onlyIfAvailableOverrides = parameterNames.onlyIfAvailableOverrides
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
		for receivedProperty in lazilyInstantiatedReceivedProperties
			where lazilyInstantiatedPropertiesSeen.insert(receivedProperty.asUnwrappedProperty).inserted
		{
			lazilyInstantiatedPropertiesToBind.append(receivedProperty.asUnwrappedProperty)
		}
		let lazilyInstantiatedInstanceProperties = lazilyInstantiatedPropertiesToBind.map(\.asValidatedForDependencyCycles)
		let lazilyInstantiatedBindingNames = Self.namesApart(
			preferredNames: lazilyInstantiatedPropertiesToBind.map { lazilyInstantiatedProperty in
				"\(lazilyInstantiatedProperty.label)_\(lazilyInstantiatedProperty.propertyType.isSendable ? "sendableLazilyInstantiated" : "lazilyInstantiated")".spelledAsJoinedIdentifier
			},
			typeDescriptions: lazilyInstantiatedInstanceProperties.map(\.typeDescription),
			namesInScope: Set(allFlatLabels)
				.union(flatReceivedParameters.map(\.label))
				.union(uncoveredDependencyNames)
				.union(onlyIfAvailableOverrides.map(\.name))
				.union(treeBindingNames)
				.union(namesDeclaredInBuilderFunctions),
			reservedNames: [],
		)
		var lazilyInstantiatedBindings = [String]()
		var lazilyInstantiatedBindingNameByProperty = [Property: String]()
		for index in lazilyInstantiatedPropertiesToBind.indices {
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
			lazilyInstantiatedBindingNameByProperty[lazilyInstantiatedProperty] = bindingName
		}
		var lazilyInstantiatedBindingNameMap = [String: [TypeDescription: String]]()
		for receivedProperty in lazilyInstantiatedReceivedProperties {
			lazilyInstantiatedBindingNameMap[receivedProperty.label, default: [:]][receivedProperty.typeDescription] = lazilyInstantiatedBindingNameByProperty[receivedProperty.asUnwrappedProperty]
		}

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

				extension \(typeName) {
				    public enum \(publicMockPlan.guardTypeName) {}
				}
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
			if let publicMock, let publicMockPlan {
				lines.append(Self.publicSafeDIOverridesStruct(
					rootChildren: treePropertyNodes,
					rootLabelMap: rootLabelMap,
					defaultFields: publicMockPlan.defaultFields,
					mockedType: instantiable,
					context: publicMock,
					indent: indent,
				))
			} else {
				lines.append(Self.generateSafeDIOverridesStruct(
					rootChildren: treePropertyNodes,
					rootLabelMap: rootLabelMap,
					onlyIfAvailableOverrides: onlyIfAvailableOverrides,
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
		for (property, flatReceived) in zip(flatReceivedProperties, flatReceivedParameters) {
			if let mockDefault = parameters.flatReceivedParameterMockDefaults[property] {
				mockParameters.append("\(bodyIndent)\(flatReceived.label): \(flatReceived.typeSource) = \(mockDefault.expression)")
			} else {
				mockParameters.append("\(bodyIndent)\(flatReceived.label): \(flatReceived.typeSource)")
			}
		}
		for flatUncovered in flatUncoveredParameters {
			if flatUncovered.isSendableAutoclosure {
				mockParameters.append("\(bodyIndent)\(flatUncovered.label): @autoclosure @escaping @Sendable () -> \(flatUncovered.typeSource)")
			} else {
				mockParameters.append("\(bodyIndent)\(flatUncovered.label): \(flatUncovered.typeSource)")
			}
		}
		if hasOverridableTree {
			mockParameters.append("\(bodyIndent)\(ReservedName.mockOverridesParameterName): SafeDIOverrides = .init()")
		}

		// Each `@Sendable` autoclosure parameter is read into a local before every builder function, under a name
		// no scope rebinds, and the value of one the mocked type itself instantiates is bound under the parameter's
		// name in the body, as a type in the tree binds it in its builder function. The body's binding hides the
		// parameter from the receivers in the tree, which read the value as they did when the parameter was one.
		var sendableAutoclosureParameters = [Property: SendableAutoclosureParameter]()
		var sendableAutoclosureBindings = [String]()
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
				sendableAutoclosureBindings.append("\(bodyIndent)let \(parameter.name) = \(parameter.localName)()")
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
		var siblingDisambiguationMap = [String: [TypeDescription: String]]()
		Self.mergeSiblingDisambiguations(into: &siblingDisambiguationMap, for: treePropertyNodes, labelMap: rootLabelMap)
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
		let treePropertyNodeBindingNames = Set(treePropertyNodes.map { node in
			siblingDisambiguationMap[node.propertyLabel]?[node.typeDescription] ?? node.propertyLabel
		})
		let rootBindingNames = treePropertyNodeBindingNames
			.union(onlyIfAvailableOverrides.map(\.name))
			.union(lazilyInstantiatedBindingNameMap.values.flatMap(\.values))
		// An alias whose label a flat received parameter has would hide that parameter from the dependencies promoted
		// beside it, whose trees receive it: the alias does not provide the receive (`isProvidedByTree`), or the mock
		// would take no parameter for it – an optional alias beside a required non-optional receive, or an alias of
		// another type. That alias is bound under a name of its own too, so that `mock()` keeps its signature.
		let (rootItems, aliasBindingNames) = Self.renamingAliases(
			in: parameterTree,
			thatRedeclare: rootBindingNames.union(flatReceivedParameters.map(\.label)),
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
			for (fillingGenerator, propertiesGeneratedLater) in rootItems.fillingGenerators {
				try await fillingGenerator.prepareFillCode(propertiesGeneratedLater: propertiesGeneratedLater)
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
			defaultValues: publicMockPlan?.constructionDefaultValues ?? [:],
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
			lines.append("extension \(typeName) {")
			lines.append("\(indent)public enum \(publicMockPlan.guardTypeName) {}")
			lines.append("}")
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
	/// - Parameter defaultValues: What a public mock passes for the mocked type's own default-valued parameters, by label,
	///   when not the binding of the label.
	private func generateReturnArgumentList(
		instantiable: Instantiable,
		disambiguationMap: [String: [TypeDescription: String]] = [:],
		defaultValues: [String: String] = [:],
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
		// So is one that instantiates a dependency the mock builds as the `LazilyInstantiated` its tree receives.
		let lazilyInstantiatedInstanceProperties = Set(propertiesToGenerate.compactMap(\.declaredLazilyInstantiatedInstanceProperty))
		var parts = [String]()
		for argument in constructionInitializer.arguments {
			if let dependency = dependenciesByLabel[argument.innerLabel] {
				// When the dep's label was sibling-disambiguated in the tree
				// (e.g. root's `service: TypeA` when a promoted sibling is also
				// labeled `service`), the bound `let` uses the disambiguated
				// name. Rewrite the reference so the Root init call finds it.
				let readsInstanceOfLazilyInstantiatedProperty = switch dependency.source {
				case .received, .instantiated:
					lazilyInstantiatedInstanceProperties.contains(dependency.property.asUnwrappedProperty)
				case .aliased, .forwarded:
					false
				}
				if readsInstanceOfLazilyInstantiatedProperty {
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
			} else if argument.hasDefaultValue, argument.label != "_" {
				// `mock()` takes an `@autoclosure` parameter as an autoclosure, or a public mock as a closure, and
				// passes its call, so the value is evaluated where the type is built.
				let parameterValue = argument.typeDescription.strippingEscaping.autoclosureValueType == nil ? argument.label : "\(argument.label)()"
				parts.append("\(argument.label.spelledAsArgumentLabel): \(defaultValues[argument.label] ?? parameterValue)")
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
			return "\(indent)let \(parameter.name) = \(parameter.localName)()"
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
	/// A class, so that the many places mock generation holds a node, in arrays of the tree's items and of its
	/// property nodes, retain one reference rather than copying every field. Every stored property is a `let`, so a
	/// node is a value nothing changes, and `Sendable`.
	final class MockParameterNode: Sendable {
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
		/// builder function is declared (`SeamHoles.valuesBindings(at:)`).
		let valuesBindings: [String]
		/// For a node that calls another module's public mock and fills some of its builders, the generator of the call,
		/// which holds the fills' code (`ScopeGenerator.fillCode(propertiesGeneratedLater:)`), and what the call passes
		/// each builder it fills, by label.
		let fillingGenerator: ScopeGenerator?
		let holeArgumentValuesByLabel: [String: String]
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
			customMockName: String?,
			concreteType: TypeDescription,
			sourceFilePath: String?,
			mockDeclarationLocation: Dependency.DeclarationLocation?,
			publicMockCall: PublicMockCall?,
			valuesBindings: [String],
			fillingGenerator: ScopeGenerator?,
			holeArgumentValuesByLabel: [String: String],
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
			self.customMockName = customMockName
			self.concreteType = concreteType
			self.sourceFilePath = sourceFilePath
			self.mockDeclarationLocation = mockDeclarationLocation
			self.publicMockCall = publicMockCall
			self.valuesBindings = valuesBindings
			self.fillingGenerator = fillingGenerator
			self.holeArgumentValuesByLabel = holeArgumentValuesByLabel
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
			builderParameterTypes = callSiteArguments.map { argument in
				(argument.typeDescription.strippingEscaping.autoclosureValueType ?? argument.typeDescription).asFunctionParameter
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
			let overridesType = "\(concreteType.asSource).SafeDIOverrides"
			return sendable
				? (type: "(@Sendable () -> \(overridesType))?", defaultValue: "nil")
				: (type: overridesType, defaultValue: ".init()")
		}

		/// The call of the public mock this node calls (see `publicMockCall`), which takes `safeDIOverrides`: the tier's
		/// parameters, and the member that configures the node, or the mock's default beneath a pruned edge, where the
		/// node has none. An erased node wraps the call in its eraser, as `constructionExpression` wraps a construction.
		/// - Parameter overridesIsSendableClosure: Whether the member that configures the node is a `@Sendable` closure
		///   (`publicMockOverridesMember(sendable:)`).
		func publicMockCallExpression(arguments: [String], overridesExpression: String?, overridesIsSendableClosure: Bool) -> String {
			var labeledArguments = zip(callSiteArguments, arguments).map { "\($0.label.spelledAsArgumentLabel): \($1)" }
			if let overridesExpression {
				let overrides = overridesIsSendableClosure ? "\(overridesExpression)?() ?? .init()" : overridesExpression
				labeledArguments.append("\(ReservedName.mockOverridesParameterName): \(overrides)")
			}
			let call = "\(concreteType.asSource).\(InstantiableVisitor.mockMethodName)(\(labeledArguments.joined(separator: ", ")))"
			return erasedToConcreteExistential ? "\(concreteExistentialType.asSource)(\(call))" : call
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
		private static func isElidedInCallSite(_ argument: Initializer.Argument, dependencyInnerLabels: Set<String>) -> Bool {
			argument.label == "_"
				&& argument.hasDefaultValue
				&& !dependencyInnerLabels.contains(argument.innerLabel)
		}

		/// The labels of `dependencies`.
		private let dependencyInnerLabels: Set<String>

		/// Construction arguments surfaced at the mock call site, with elided
		/// non-dependency unlabeled defaults removed.
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
			return "(\(parameterTypes)) -> \(instantiatedTypeDescription.asSource)"
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
		) -> String {
			let defaultCall = defaultBuilderCall(
				arguments: arguments,
				overrideReachable: overrideReachable,
				handWrittenMockDefaultParameters: handWrittenMockDefaultParameters,
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
		/// `callSiteArgumentsForPrunedOverride` rather than `callSiteArguments`,
		/// and the same `handWrittenMockDefaultParameters` it was given.
		/// Zipping against the wrong signature would shift labels for arguments
		/// that follow an elided default (e.g. `init(a: A, b: B = ..., c: C)`
		/// with `b` elided would emit `C`'s value under label `b`).
		private func defaultBuilderCall(
			arguments: [String],
			overrideReachable: Bool,
			handWrittenMockDefaultParameters: [DefaultParameter],
		) -> String {
			let methodName: String = if useMockInitializer {
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
			let labeledArguments = zip(surfacedArguments, arguments)
				.map { $0.0.label == "_" ? $0.1 : "\($0.0.label.spelledAsArgumentLabel): \($0.1)" }
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
					      argument.label != "_",
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

	/// Collects the nodes of all unique configuration types in this scope's mock parameter tree,
	/// in the order this root reaches them. `generateMockCode` keeps the first root's node for each
	/// type, in alphabetical root order, and generates its struct once with `generateConfigurationStruct`.
	func collectConfigurationTypes() async -> [MockParameterNode] {
		let parameterTree = await rootMockParameterTree
		return await Self.collectUniqueConfigurationTypes(from: parameterTree.propertyNodes)
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

		// Roots only appear at the top level, never as children here — so the
		// `.root` case is not part of the reachable pattern space and is omitted.
		for child in orderedChildren(propertiesGeneratedLater: propertiesGeneratedLater) {
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
					customMockName: childInstantiable.customMockName,
					concreteType: childInstantiable.concreteInstantiable,
					sourceFilePath: childInstantiable.sourceFilePath,
					mockDeclarationLocation: childInstantiable.mockDeclarationLocation,
					publicMockCall: childGenerator.publicMockCall,
					valuesBindings: childGenerator.valuesBindingsBeforeBuilderFunction,
					fillingGenerator: childGenerator.fillsABuilder ? childGenerator : nil,
					holeArgumentValuesByLabel: childGenerator.holeArgumentValuesByLabel,
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
					? property.typeDescription.asInstantiatedType.asFunctionParameter.asSource
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
	/// takes as parameters (see `PublicMockCall.passedUpBuilders`), each with the type whose mock it is passed to, and those
	/// a scope beneath the mock root's level that encloses a leaf reading one declares the label of, which would hide the
	/// parameter from that leaf.
	private static func passedUpBuilders(in nodes: [MockParameterNode]) -> (calledTypeByProperty: [Property: TypeDescription], hidden: Set<Property>) {
		var calledTypeByProperty = [Property: TypeDescription]()
		var hidden = Set<Property>()
		// A stack of the nodes left to visit, each with the labels the builder functions enclosing it declare, since a mock
		// tree can be as deep as the module has types. A subtree that calls no public mock passes nothing up.
		var nodesToVisit = nodes.filter(\.subtreeCallsPublicMock).map { (node: $0, labelsDeclaredAbove: Set<String>()) }
		while let (node, labelsDeclaredAbove) = nodesToVisit.popLast() {
			var labelsDeclared = labelsDeclaredAbove
			for dependency in node.dependencies {
				switch dependency.source {
				case .received:
					// A builder's type names the called mock's own enum, so one type's mock is passed it, whichever call it is.
					if let publicMockCall = node.publicMockCall, publicMockCall.passesUpBuilder(receivedAs: dependency.property) {
						calledTypeByProperty[dependency.property] = node.concreteType
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
		return (calledTypeByProperty, hidden)
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
	static func identifierSafeNames(
		for entries: [(label: String, suffixTypes: [TypeDescription])],
		besideEntriesKeepingTheirNames entriesKeepingTheirNames: [(label: String, suffixTypes: [TypeDescription])] = [],
		reservedNames: Set<String>,
	) -> [String] {
		let suffixesPerEntry = entries.map { $0.suffixTypes.map(\.asIdentifier) }
		let suffixesPerEntryKeepingItsName = entriesKeepingTheirNames.map { $0.suffixTypes.map(\.asIdentifier) }
		var takenNames = reservedNames
		return entries.indices.map { index in
			let suffixes = suffixesPerEntry[index]
			let suffix = suffixes.indices.first { position in
				!entries.indices.contains { otherIndex in
					otherIndex != index
						&& entries[otherIndex].label == entries[index].label
						&& suffixesPerEntry[otherIndex][position] == suffixes[position]
				}
					&& !entriesKeepingTheirNames.indices.contains { otherIndex in
						entriesKeepingTheirNames[otherIndex].label == entries[index].label
							&& suffixesPerEntryKeepingItsName[otherIndex][position] == suffixes[position]
					}
			}.map { suffixes[$0] } ?? suffixes[suffixes.count - 1]
			var name = "\(entries[index].label)_\(suffix)".spelledAsJoinedIdentifier
			while takenNames.contains(name) {
				name = "\(name)_".spelledAsJoinedIdentifier
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
	/// `async` for the reason `generateMockBodyBindings` is.
	private static func collectUniqueConfigurationTypes(
		from nodes: [MockParameterNode],
	) async -> [MockParameterNode] {
		var seen = Set<String>()
		var result = [MockParameterNode]()

		func walk(_ node: MockParameterNode, ancestorTypes: Set<String> = []) async {
			let key = node.concreteType.asSource
			// Skip nodes whose type matches an ancestor — self-referencing cycle.
			guard !ancestorTypes.contains(key) else { return }
			var childAncestors = ancestorTypes
			childAncestors.insert(key)
			// Process children first (depth-first). Only property children
			// produce configuration structs; aliases are plain `let` bindings.
			for child in node.propertyChildren {
				await walk(child, ancestorTypes: childAncestors)
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
			await walk(node)
		}
		return result
	}

	/// Generates the `SafeDIOverrides` struct. Configuration type references
	/// use qualified names (e.g., `ChildA.SafeDIMockConfiguration`).
	private static func generateSafeDIOverridesStruct(
		rootChildren: [MockParameterNode],
		rootLabelMap: [String: [TypeDescription: String]],
		onlyIfAvailableOverrides: [OnlyIfAvailableOverride],
		indent: String,
	) -> String {
		let innerIndent = "\(indent)\(standardIndent)"
		let memberIndent = "\(innerIndent)\(standardIndent)"

		var lines = [String]()
		lines.append("\(indent)/// Overrides for the mock dependency tree.")
		lines.append("\(indent)struct SafeDIOverrides {")

		// Generate SafeDIOverrides init with root-level children and onlyIfAvailable entries.
		lines.append("\(innerIndent)init(")
		var initParameters = rootChildren.map { child in
			let label = disambiguatedLabel(for: child, labelMap: rootLabelMap)
			if let publicMockOverridesMember = child.publicMockOverridesMember(sendable: child.requiresSendable) {
				return "\(memberIndent)\(label): \(publicMockOverridesMember.type) = \(publicMockOverridesMember.defaultValue)"
			} else if child.needsConfigurationStruct {
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
			if let publicMockOverridesMember = child.publicMockOverridesMember(sendable: child.requiresSendable) {
				lines.append("\(innerIndent)let \(label): \(publicMockOverridesMember.type)")
			} else if child.needsConfigurationStruct {
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
	/// cross-root struct-per-type dedup produces a consistent annotation. Such a struct
	/// also stores each labeled default-valued parameter that is not a closure as a
	/// `@Sendable` closure returning the value, which `resolveBuilderArguments` calls.
	private static func generateConfigurationStruct(
		for node: MockParameterNode,
		indent: String,
		cycleEdges: Set<CycleEdge>,
		requiresSendable: Bool,
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
			if let publicMockOverridesMember = child.publicMockOverridesMember(sendable: requiresSendable || child.requiresSendable) {
				initParameters.append("\(innerIndent)\(standardIndent)\(label): \(publicMockOverridesMember.type) = \(publicMockOverridesMember.defaultValue)")
				storedProperties.append("\(innerIndent)let \(label): \(publicMockOverridesMember.type)")
			} else if child.needsConfigurationStruct {
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
			let typeSource = defaultParameter.valueTypeDescription.asSource
			// Only add @Sendable if this struct requires it AND the type doesn't already have it.
			let closureSendable = (requiresSendable && !typeSource.contains("@Sendable")) ? "@Sendable " : ""
			if defaultParameter.isAutoclosure, !requiresSendable {
				// An `@autoclosure` parameter is evaluated where the type is built: the struct stores a closure that
				// returns the value, which its initializer takes as an autoclosure, as the parameter does, and the mock
				// calls it once per construction (`resolveBuilderArguments`).
				initParameters.append("\(innerIndent)\(standardIndent)\(defaultParameter.label): @autoclosure @escaping () -> \(typeSource) = \(autoclosureDefault(defaultExpression(defaultParameter)))")
				storedProperties.append("\(innerIndent)let \(defaultParameter.label): () -> \(typeSource)")
			} else if defaultParameter.isClosureType, !defaultParameter.isAutoclosure {
				initParameters.append("\(innerIndent)\(standardIndent)\(defaultParameter.label): \(closureSendable)@escaping \(typeSource) = \(defaultExpression(defaultParameter))")
				storedProperties.append("\(innerIndent)let \(defaultParameter.label): \(closureSendable)\(typeSource)")
			} else if requiresSendable {
				// A `@Sendable` builder function cannot capture the value when its type is not `Sendable`, and
				// SafeDI cannot tell whether it is, so the struct stores a `@Sendable` closure that returns the
				// value and the mock calls it where it builds the type, which evaluates the default once per
				// construction, as production does. The initializer takes the value as an autoclosure, so a
				// caller still passes a value. Swift rejects `@Sendable` on a typealias, so a typealiased function
				// type is stored this way too, even when the parameter is declared `@escaping`.
				initParameters.append("\(innerIndent)\(standardIndent)\(defaultParameter.label): @autoclosure @escaping @Sendable () -> \(typeSource) = \(autoclosureDefault(defaultExpression(defaultParameter)))")
				storedProperties.append("\(innerIndent)let \(defaultParameter.label): @Sendable () -> \(typeSource)")
			} else {
				// A parameter declared `@escaping` is of a function type, which the initializer stores, so it takes the
				// value `@escaping` too, also when the type is a typealias of a function type.
				let escaping = defaultParameter.isDeclaredEscaping ? "@escaping " : ""
				initParameters.append("\(innerIndent)\(standardIndent)\(defaultParameter.label): \(escaping)\(typeSource) = \(defaultExpression(defaultParameter))")
				storedProperties.append("\(innerIndent)let \(defaultParameter.label): \(typeSource)")
			}
			assignments.append("\(innerIndent)\(standardIndent)self.\(defaultParameter.label) = \(defaultParameter.label)")
		}

		// Builder parameter (always last, unlabeled). Optional with nil default so that
		// the default construction (which may be @MainActor) is called in mock()
		// rather than referenced in this nonisolated init.
		let closureType = node.concreteBuilderClosureType
		initParameters.append("\(innerIndent)\(standardIndent)_ \(ReservedName.configurationBuilderPropertyName): (\(sendableAnnotation)\(closureType))? = nil")
		assignments.append("\(innerIndent)\(standardIndent)self.\(ReservedName.configurationBuilderPropertyName) = \(ReservedName.configurationBuilderPropertyName)")
		storedProperties.append("\(innerIndent)/// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.")
		storedProperties.append("\(innerIndent)let \(ReservedName.configurationBuilderPropertyName): (\(sendableAnnotation)\(closureType))?")

		// Emit init.
		lines.append("\(innerIndent)init(")
		lines.append(initParameters.joined(separator: ",\n"))
		lines.append("\(innerIndent)) {")
		lines.append(contentsOf: assignments)
		lines.append("\(innerIndent)}")

		// Emit stored properties. They are `let`, not `private(set) var`, which would keep an extension initializer from assigning
		// them one by one but costs Debug builds of mocks; the Manual asks users to build a configuration through its
		// initializers instead (see "Configuration fields are `let`" in `.claude/rules/mock-generation.md`).
		lines.append("")
		lines.append(contentsOf: storedProperties)

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
						lines.append("\(indent)\(valuesBinding)")
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

				let relativePath = nodePath
					.replacingOccurrences(of: "\(ReservedName.mockOverridesParameterName).", with: "")
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
				)
				// The member that configures a node calling another module's public mock is a `@Sendable` closure where
				// the struct holding it is read inside a `@Sendable` builder function.
				let publicMockOverridesIsSendableClosure = node.requiresSendable || (parentConcreteType.map(sendableConfigurationTypeNames.contains) ?? false)
				let constructionExpression = mockConstructionExpression(
					for: node,
					overrideExpression: overrideExpression,
					arguments: arguments,
					overrideReachable: thisOverrideReachable,
					handWrittenMockDefaultParameters: nodeHandWrittenMockDefaultParameters,
					publicMock: publicMock,
					publicMockOverridesIsSendableClosure: publicMockOverridesIsSendableClosure,
				)
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
					lines.append("\(indent)let \(outerBindingName): \(node.instantiatedTypeDescription.asSource) = \(functionName)(\(closerArguments))")
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
					let propertyTypeName = node.instantiatedTypeDescription.asSource
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
							),
							overrideReachable: thisOverrideReachable,
							handWrittenMockDefaultParameters: nodeHandWrittenMockDefaultParameters,
							publicMock: publicMock,
							publicMockOverridesIsSendableClosure: publicMockOverridesIsSendableClosure,
						)
					} else {
						constructionExpression
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
			return buildSiteCode(of: alias.property, at: holeSite, functionName: holeFunctionName, readingInstancesOf: alias.holeSiteLazilyInstantiatedInstanceProperties).split(separator: "\n").map(String.init)
				.map { "\(indent)\($0)" }
				.joined(separator: "\n")
		}
		guard !alias.isBoundToNil else {
			return referencingDeclaration(of: "let \(alias.property.asSource) = nil", by: alias.declarationReference)
				.split(separator: "\n")
				.map { "\(indent)\($0)" }
				.joined(separator: "\n")
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
				loop: alias.loop,
				declaredProperty: alias.declaredProperty ?? alias.property,
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
	) -> [String] {
		// Each label names one dependency: `validateDependencyLabelsAreDistinct` rejects a declaration in a generated tree that repeats one.
		let dependenciesByLabel = Dictionary(grouping: node.dependencies, by: \.property.label).compactMapValues(\.first)
		let relativePath = nodePath
			.replacingOccurrences(of: "\(ReservedName.mockOverridesParameterName).", with: "")
			.replacingOccurrences(of: ".", with: "_")
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
				)
			} else if !overrideReachable {
				// The struct is built afresh, so nothing is read from `SafeDIOverrides`, even inside a `@Sendable` function.
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
	static func dependencyArgument(
		_ argument: Initializer.Argument,
		of dependency: Dependency,
		for node: MockParameterNode,
		lazilyInstantiatedBindingNames: [String: [TypeDescription: String]],
		uncoveredDependencyNames: [String: [TypeDescription: String]],
	) -> String {
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
		} else if case .instantiated = dependency.source,
		          let parameterName = uncoveredDependencyNames[argument.innerLabel]?[dependency.property.typeDescription]
		{
			// The `mock()` parameter of an uncovered dependency, named apart from a name in scope.
			parameterName
		} else {
			argument.innerLabel
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
		for line in await fillingGenerator.fillCode(propertiesGeneratedLater: node.fillPropertiesGeneratedLater).joined(separator: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
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
				var lines = ["\(functionIndent)\(decorator)func \(receivedFunctionName)(\(functionParameters)) -> \(node.instantiatedTypeDescription.asSource) {"]
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

			let functionReturnType = node.instantiatedTypeDescription.asSource
			// The payloads of the cases on the routes to the places beneath this function, bound before it.
			for valuesBinding in node.valuesBindings {
				lines.prelude.append("\(indent)\(valuesBinding)")
			}
			lines.function.append("\(indent)\(functionDecorator)func \(functionName)(\(functionArguments)) -> \(functionReturnType) {")
			// A member of a loop of builders first wraps again the functions of the members its tree receives inside the
			// loop, so each receiver beneath reads a wrapper this call made.
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
			let returnKeyword = rebindingLines.isEmpty && preamble.isEmpty && childBindings.isEmpty && receiverBindings.isEmpty && sendableAutoclosureBindings.isEmpty ? "" : "return "
			let builtConstructionExpression = mockConstructionExpression(
				for: node,
				overrideExpression: functionOverrideExpression,
				arguments: functionConstructionArguments,
				overrideReachable: overridePathReachable,
				handWrittenMockDefaultParameters: nodeHandWrittenMockDefaultParameters,
				publicMock: publicMock,
				publicMockOverridesIsSendableClosure: publicMockOverridesIsSendableClosure,
			)
			// A public mock takes a lazily instantiated dependency it builds by value, so its builder function returns
			// the value its caller passed, if any – unless a cycle closes on the function, whose cycle-closing scopes build
			// the declaration they repeat again, as production does: then the wrapper's closure returns it instead.
			let constructionExpression = if let promotedParameterName, node.property.propertyType.isLazilyInstantiated, !node.isReferencedByCycleClosingScope {
				passing(promotedParameterName, orBuilding: builtConstructionExpression)
			} else {
				builtConstructionExpression
			}
			lines.function.append("\(innerIndent)\(returnKeyword)\(constructionExpression)")
			lines.function.append("\(indent)}")
		}
		if let receivedFunction = loopMemberEmission?.receivedFunction {
			lines.function.append(contentsOf: receivedFunction.lines)
		}

		// Emit the Instantiator/ErasedInstantiator construction.
		let unwrappedType = node.typeDescription.unwrapped
		let unwrappedTypeDescription = unwrappedType.spelledForConstruction
		let outerBinding = unwrappedType.isConstructedByAnnotation ? "\(outerBindingName): \(unwrappedType.asSource)" : outerBindingName

		// The builder function now returns the property type directly (including
		// wrapping for erasedToConcreteExistential), so no outer wrapping needed.
		let instantiatorConstruction = if let promotedParameterName, node.property.propertyType.isLazilyInstantiated, node.isReferencedByCycleClosingScope {
			"""
			\(unwrappedTypeDescription) {
			\(indent)\(standardIndent)\(passing(promotedParameterName, orBuilding: "\(functionName)(\(forwardedArguments))"))
			\(indent)}
			"""
		} else {
			mockInstantiatorConstruction(
				of: node.typeDescription,
				handing: loopMemberEmission?.receivedFunction?.name ?? functionName,
				forwardedArguments: forwardedArguments,
				indent: indent,
			)
		}

		if loopMemberEmission?.declaresBinding == false {
			// Only the wrappers its loop makes again hand the member's function.
		} else if let promotedParameterName, !node.property.propertyType.isLazilyInstantiated {
			// A public mock takes an instantiator it builds for a received dependency as itself.
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
		/// the stage calls made before the function.
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
			)
		}
	}

	/// The expression that builds `node`: a call of its construction function in a public mock, when its type has a
	/// configuration (`publicConstructionExpression`), and otherwise `MockParameterNode.constructionExpression`.
	/// - Parameter publicMockOverridesIsSendableClosure: For a node that calls another module's public mock, whether the
	///   member that configures it is a `@Sendable` closure: the node is built inside a `@Sendable` builder function, or
	///   the struct that holds the member is read inside one in some mock (`sendableConfigurationTypeNames`).
	private static func mockConstructionExpression(
		for node: MockParameterNode,
		overrideExpression: String?,
		arguments: [String],
		overrideReachable: Bool,
		handWrittenMockDefaultParameters: [MockParameterNode.DefaultParameter],
		publicMock: PublicMockEmission?,
		publicMockOverridesIsSendableClosure: Bool,
	) -> String {
		if let publicMockCall = node.publicMockCall, publicMockCall.takesOverrides {
			node.publicMockCallExpression(arguments: arguments, overridesExpression: overrideExpression, overridesIsSendableClosure: publicMockOverridesIsSendableClosure)
		} else if publicMock != nil, node.needsConfigurationStruct {
			publicConstructionExpression(for: node, overrideExpression: overrideExpression, arguments: arguments)
		} else {
			node.constructionExpression(
				overrideExpression: overrideExpression,
				arguments: arguments,
				overrideReachable: overrideReachable,
				handWrittenMockDefaultParameters: handWrittenMockDefaultParameters,
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
	/// This field, declaring `property`, a form of its own property.
	func withProperty(_ property: Property) -> SeamSignature.Hole.Field {
		SeamSignature.Hole.Field(
			property: property,
			access: access,
			accessCause: accessCause,
			declaringType: declaringType,
			declarationLocation: declarationLocation,
			isReceivedOnlyIfAvailable: isReceivedOnlyIfAvailable,
			deferral: deferral,
		)
	}
}
