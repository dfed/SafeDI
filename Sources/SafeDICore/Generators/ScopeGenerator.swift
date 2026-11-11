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
		builtInlineSeamComment: String?,
		seamCall: SeamCall? = nil,
		publicMockCall: PublicMockCall? = nil,
		seamRoot: SeamRoot? = nil,
		holeCallArguments: [HoleCallArgument] = [],
		passedUpHoles: [SeamSignature.Hole] = [],
		stageCalls: [String] = [],
		fill: (hole: SeamSignature.Hole, key: String, functionName: String, boundLabels: Set<String>)? = nil,
		constructsWithHandWrittenMock: Bool = false,
		cycleParameters: [CycleParameter] = [],
		builtCycleParameters: [CycleParameter] = [],
		cycleParameterUnavailableProperties: Set<Property> = [],
		callSiteLazilyInstantiatedInstanceProperties: Set<Property>? = nil,
	) {
		self.builtInlineSeamComment = builtInlineSeamComment
		self.constructsWithHandWrittenMock = constructsWithHandWrittenMock
		self.closedOnDeclaration = closedOnDeclaration
		self.cycleParameters = cycleParameters
		self.cycleParameterUnavailableProperties = cycleParameterUnavailableProperties
		self.callSiteLazilyInstantiatedInstanceProperties = callSiteLazilyInstantiatedInstanceProperties ?? lazilyInstantiatedInstanceProperties
		self.publicMockCall = publicMockCall
		self.holeCallArguments = holeCallArguments
		fillKey = fill?.key
		fillStructBoundLabels = fill?.boundLabels ?? []
		ownerPropertyStack = []
		self.passedUpHoles = passedUpHoles
		self.stageCalls = stageCalls
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
		fieldsCarriedBySites = containsBuildSite ? Set(propertiesToGenerate.flatMap(\.fieldsCarriedBySites)) : []
		passesUpBuilder = !passedUpHoles.isEmpty || propertiesToGenerate.contains(where: \.passesUpBuilder)
		// This runs at every scope of every tree, and nearly every child is outside every cycle.
		var childCycleClosedOnDeclarations = Set<BuiltDeclaration>()
		var childrenTakePartInCycle = false
		for child in propertiesToGenerate where child.isReferencedByCycleClosingScope || !child.cycleClosedOnDeclarations.isEmpty {
			childCycleClosedOnDeclarations.formUnion(child.cycleClosedOnDeclarations)
			childrenTakePartInCycle = true
		}
		self.childrenTakePartInCycle = childrenTakePartInCycle
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
		// A call inside a fill of its seam's call refers to every fill of the enclosing call by name. Where a `@Sendable`
		// builder function that does not enclose a fill holds the reference – one between the call and the fill, a staged
		// fill's later stage, or the call's own – the fill must be `@Sendable` too, and so must a fill the call passes to a
		// seam that takes it `@Sendable`. Nearly no scope holds such a call.
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
		for child in propertiesToGenerate where !child.referencedFillNamesByKey.isEmpty {
			referencedFillNamesByKey.merge(child.referencedFillNamesByKey) { name, _ in name }
			fillKeysReferencedFromSendableFunction.formUnion(child.fillKeysReferencedFromSendableFunction)
		}
		let referencedFillKeys = Set(referencedFillNamesByKey.keys)
		if buildsInSendableFunction || (fill.map { $0.hole.stages.count > 1 } ?? false) {
			fillKeysReferencedFromSendableFunction.formUnion(referencedFillKeys)
		}
		// A call's own fills are declared in the function that makes it, which encloses every reference to them.
		let ownFillKeys = Set(propertiesToGenerate.compactMap(\.fillKey))
		sendableFillKeys = fillKeysReferencedFromSendableFunction.intersection(ownFillKeys)
		// A call's fills whose hole has a field bound from a deferred parameter read it from the caller's scope, unless a
		// call inside one of them passes it on beneath another declaration of the label. Nearly no scope calls such a seam.
		let fillsWithDeferredFields = propertiesToGenerate.compactMap { fill -> (fill: ScopeGenerator, hole: SeamSignature.Hole, key: String)? in
			guard let hole = fill.fillHole, let key = fill.fillKey, hole.stages.joined().contains(where: \.isDeferredParameter) else { return nil }
			return (fill, hole, key)
		}
		var fillDeferredLabelsHiddenByReenteringCalls = [String: Set<String>]()
		var fillStructBoundLabelsChangedInTree = propertiesToGenerate.contains(where: \.fillStructBoundLabelsChangedInTree)
		if !fillsWithDeferredFields.isEmpty {
			let hiddenByFillKey = DependencyTreeGenerator.hiddenByReenteringCalls(ofFills: propertiesToGenerate)
			for (fill, hole, key) in fillsWithDeferredFields {
				let deferredLabels = Set(hole.stages.joined().filter(\.isDeferredParameter).map(\.property.label))
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
			for property in child.receivedProperties
				where isReceivedFromAncestors(property)
				&& (child.requiredReceivedProperties.contains(property) || !providesAFormReadByOnlyIfAvailableReceive(of: property))
			{
				receivedProperties.insert(property)
				if child.requiredReceivedProperties.contains(property) {
					requiredReceivedProperties.insert(property)
				}
			}
		}
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
					declaredProperties: propertiesToDeclare,
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
					declaredProperties: propertiesToDeclare,
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
		var cycleClosingRedeclaredLabels = [BuiltDeclaration: Set<String>]()
		if let closedOnDeclaration {
			cycleClosingRedeclaredLabels[closedOnDeclaration] = []
		} else if childrenTakePartInCycle {
			for child in propertiesToGenerate {
				for (closedOnDeclaration, labels) in child.cycleClosingRedeclaredLabels {
					cycleClosingRedeclaredLabels[closedOnDeclaration, default: []].formUnion(labels)
				}
			}
		}
		var foundCycleParameters = [CycleParameter]()
		if let property, let declaration, !isPropertyCycle, let labels = cycleClosingRedeclaredLabels.removeValue(forKey: declaration) {
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
			var receivedLabels = Set<String>()
			for receivedProperty in receivedProperties where labels.contains(receivedProperty.label) && !ownDeclaredLabels.contains(receivedProperty.label) {
				receivedLabels.insert(receivedProperty.label)
			}
			if !receivedLabels.isEmpty {
				foundCycleParameters = CycleParameter.parameters(
					firstReceives: Self.inOrderTheBodyFirstReceives(
						ofLabels: receivedLabels,
						builtProperty: property,
						builtType: instantiable.concreteInstantiable,
						ownDependencies: instantiable.dependencies,
						children: propertiesToGenerate,
					),
					receivedProperties: receivedProperties,
					requiredReceivedProperties: requiredReceivedProperties,
					requiredAliasFulfillingProperties: requiredAliasFulfillingProperties,
					onlyIfAvailableUnwrappedReceivedProperties: onlyIfAvailableUnwrappedReceivedProperties,
				)
			}
		}
		if !isPropertyCycle, !cycleClosingRedeclaredLabels.isEmpty {
			// This scope's declarations, forwarded properties and own parameters are between each of those cycle-closing
			// scopes and the scope it closes on.
			var declaredLabels = Set(propertiesToDeclare.map(\.label))
			for forwardedProperty in forwardedProperties {
				declaredLabels.insert(forwardedProperty.label)
			}
			for parameter in cycleParameters {
				declaredLabels.insert(parameter.property.label)
			}
			cycleClosingRedeclaredLabels = cycleClosingRedeclaredLabels.mapValues { $0.union(declaredLabels) }
		}
		self.cycleClosingRedeclaredLabels = cycleClosingRedeclaredLabels
		self.foundCycleParameters = foundCycleParameters
		cycleParametersChangedInTree = foundCycleParameters != builtCycleParameters
			|| propertiesToGenerate.contains(where: \.cycleParametersChangedInTree)
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
		cycleParameters = []
		cycleParameterUnavailableProperties = []
		callSiteLazilyInstantiatedInstanceProperties = []
		cycleClosingRedeclaredLabels = [:]
		foundCycleParameters = []
		cycleParametersChangedInTree = false
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
		ownerPropertyStack = []
		holeCallArguments = []
		passedUpHoles = []
		stageCalls = []
		containsBuildSite = false
		fieldsCarriedBySites = []
		passesUpBuilder = false
		fillKey = nil
		fillStructBoundLabels = []
		fillDeferredLabelsHiddenByReenteringCalls = [:]
		fillStructBoundLabelsChangedInTree = false
		constructsWithHandWrittenMock = false
		referencedFillNamesByKey = [:]
		fillKeysReferencedFromSendableFunction = []
		sendableFillKeys = []
	}

	/// The generator of a hole: a site in a seam's tree of `holeProperty`, which the builder the seam's generated
	/// initializer takes builds from the values in scope there, `site`'s fields. It receives nothing: the scopes
	/// beneath it are the fill's, which the module that fills the builder generates. `site` is `nil` in a tree built
	/// only to compute the seam's signature, which generates nothing.
	init(
		holeProperty: Property,
		erasedToConcreteExistential: Bool,
		site: SeamSignature.Hole?,
		ownerPropertyStack: [Property],
	) {
		scopeData = .hole(property: holeProperty, erasedToConcreteExistential: erasedToConcreteExistential, site: site)
		self.ownerPropertyStack = ownerPropertyStack
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
		declaration = nil
		cycleClosedOnDeclarationsReferencedFromSendableFunction = []
		buildsInSendableFunction = false
		declaresBuilderFunction = false
		childrenTakePartInCycle = false
		cycleParameters = []
		cycleParameterUnavailableProperties = []
		callSiteLazilyInstantiatedInstanceProperties = []
		cycleClosingRedeclaredLabels = [:]
		foundCycleParameters = []
		cycleParametersChangedInTree = false
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
		holeCallArguments = []
		passedUpHoles = []
		stageCalls = []
		containsBuildSite = true
		fieldsCarriedBySites = Set(site?.stages.joined().map(\.property) ?? [])
		passesUpBuilder = false
		fillKey = nil
		fillStructBoundLabels = []
		fillDeferredLabelsHiddenByReenteringCalls = [:]
		fillStructBoundLabelsChangedInTree = false
		constructsWithHandWrittenMock = false
		referencedFillNamesByKey = [:]
		fillKeysReferencedFromSendableFunction = []
		sendableFillKeys = []
	}

	/// The generator of a fill: the function the module that calls a seam generates for one of its holes, which binds
	/// the fields of the site's scope struct that `child`, the generator of the hole's property as the fulfilling
	/// type builds it, reads. The fields it binds from the struct, those `boundLabels` names, are declared here, so a
	/// receive they provide is not received from the scopes enclosing the call (see `fillStructBoundLabels`).
	init(fill hole: SeamSignature.Hole, key: String, functionName: String, boundLabels: Set<String>, child: ScopeGenerator) {
		self.init(
			instantiable: Instantiable(
				instantiableType: hole.property.typeDescription.asInstantiatedType,
				isRoot: false,
				initializer: nil,
				additionalInstantiables: nil,
				dependencies: [],
				declarationType: .structType,
				access: AccessDeclaration(level: .internal),
			),
			property: nil,
			propertiesToGenerate: [child],
			propertiesToDeclare: Self.fieldForms(of: hole, boundLabels: boundLabels),
			unavailableOptionalProperties: [],
			lazilyInstantiatedInstanceProperties: [],
			forwardedLazilyInstantiatedInstanceProperties: [],
			erasedToConcreteExistential: false,
			isPropertyCycle: false,
			builtInlineSeamComment: nil,
			fill: (hole, key, functionName, boundLabels),
		)
	}

	/// The properties a fill of `hole` declares: the property of each field of the site's scope struct it binds – each
	/// labeled in `boundLabels` – and, for a lazily instantiated field, the instance a receive reads by value.
	static func fieldForms(of hole: SeamSignature.Hole, boundLabels: Set<String>) -> Set<Property> {
		var fieldForms = Set<Property>()
		for field in hole.stages.joined() where boundLabels.contains(field.property.label) {
			fieldForms.insert(field.property)
			if let instanceProperty = field.property.asLazilyInstantiatedInstancePropertyOfDeclaredBinding {
				fieldForms.insert(instanceProperty)
			}
		}
		return fieldForms
	}

	/// The name of the function a caller generates to fill `hole`'s builder, unless a fill enclosing it, or a builder the
	/// seam whose tree holds it takes, has that name (see `ScopeGeneratorUnderConstruction`).
	static func fillFunctionName(of hole: SeamSignature.Hole) -> String {
		functionName(toBuildPropertyNamed: hole.builderLabel)
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

	/// What identifies a fill: the site it fills, by the seam whose tree holds the site and the name of the site's scope
	/// struct, never by the seam whose call the fill is declared for, so a call inside the fill of the seam that holds
	/// the site, or of a seam that passes the site's builder up, passes the fill.
	static func fillKey(of hole: SeamSignature.Hole) -> String {
		"\(hole.scopeSeamType.asSource) \(hole.scopeTypeName)"
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
		declaredProperties.contains(property)
			|| forwardedProperties.contains(property)
			|| (property.typeDescription.isOptional
				&& (declaredProperties.contains(property.asUnwrappedProperty) || forwardedProperties.contains(property.asUnwrappedProperty)))
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
		/// The seam whose builder for `sendableBuilder` a `@Sendable` stage of a fill fills, when that stage is what
		/// captures the wrapper, or `nil` when a builder function does.
		let capturingFillSeamType: TypeDescription?
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
			guard case let .property(childInstantiable, childProperty, _, _, isPropertyCycle, seamCall) = child.generator.scopeData else { continue }
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
		await publicMockTierOmissions(of: instantiable, propertiesGeneratedLater: [], declarationsByLabel: [:], enclosingCycleFunctions: [:]).judged()
	}

	/// - Parameter enclosingCycleFunctions: The builder functions enclosing this scope that lazy cycles close on and that
	///   take parameters (see `CycleParameter`), by the declaration each builds.
	private func publicMockTierOmissions(
		of instantiable: Instantiable,
		propertiesGeneratedLater: Set<Property>,
		declarationsByLabel: [String: [VisibleDeclaration]],
		enclosingCycleFunctions: [BuiltDeclaration: ObjectIdentifier],
	) async -> OmissionFindings<PublicMockTierOmission> {
		let declaringType = instantiable.concreteInstantiable
		var declarationLocationByProperty = [Property: Dependency.DeclarationLocation?]()
		for dependency in instantiable.dependencies where !dependency.source.isReceived {
			declarationLocationByProperty[dependency.property] = dependency.declarationLocation
		}
		func visibleDeclaration(of property: Property, instanceProperty: Property?) -> VisibleDeclaration {
			VisibleDeclaration(
				property: property,
				instanceProperty: instanceProperty,
				// A property a mock root promotes is declared by no type of the tree.
				declaringType: declarationLocationByProperty[property] == nil ? nil : declaringType,
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
			} else {
				// This scope calls the child's builder function, which, when a lazy cycle closes on it and it takes parameters,
				// it passes them as each cycle-closing scope does. The function's body reads its parameters, which hide every
				// declaration of their labels where it is called, as generation's do.
				let function = ObjectIdentifier(child.generator)
				findings.recordCalls(by: child, of: function, among: childDeclarationsByLabel)
				await findings.append(contentsOf: child.generator.publicMockTierOmissions(
					of: childInstantiable,
					propertiesGeneratedLater: child.generator.bodyPropertiesGeneratedLater(child.propertiesGeneratedLater),
					declarationsByLabel: child.generator.bodyDeclarations(function: function, enclosing: childDeclarationsByLabel),
					enclosingCycleFunctions: child.generator.bodyEnclosingCycleFunctions(function: function, enclosing: enclosingCycleFunctions),
				))
			}
		}
		return findings
	}

	/// Each call in the mock tree rooted at this scope of another module's public mock whose condition the calling
	/// module's mocks do not compile under, with the dependency in the tree that leads to it.
	func publicMockCallsUnderOtherMockCondition(ofTreeRootedAt instantiable: Instantiable) async -> [PublicMockCallUnderOtherMockCondition] {
		var calls = [PublicMockCallUnderOtherMockCondition]()
		// Depth first, on a stack of its own, since a mock tree can be as deep as the module has types.
		var scopesToVisit = [(generator: self, instantiable: instantiable)]
		while let (generator, instantiable) = scopesToVisit.popLast() {
			for child in generator.propertiesToGenerate {
				guard case let .property(childInstantiable, property, _, _, isPropertyCycle, _) = child.scopeData, !isPropertyCycle else { continue }
				if let publicMockCall = child.publicMockCall {
					if !publicMockCall.mockConditionsAgree {
						calls.append(PublicMockCallUnderOtherMockCondition(
							publicMockCall: publicMockCall,
							referenceLocation: instantiable.dependencies.first { $0.property.label == property.label }?.declarationLocation ?? instantiable.declarationLocation,
						))
					}
				} else {
					scopesToVisit.append((generator: child, instantiable: childInstantiable))
				}
			}
		}
		return calls
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
		/// For a `@Sendable` stage of a fill, the seam whose builder for `property` it fills.
		var fillSeamType: TypeDescription?
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
		for dependency in instantiable.dependencies where dependency.source.isReceived && !unavailableProperties.contains(dependency.property) {
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
				// A fill is declared where the seam is called, and builds the hole's property in its last stage, each stage
				// after the first a `@Sendable` function, and the first too where the seam takes the builder `@Sendable` or a
				// `@Sendable` function refers to the fill. Each stage binds the fields of its struct the fill binds; its tree
				// reads every other label from the caller's scope – a field bound from a deferred parameter included – as it
				// would inline, so a `@Sendable` function in the fill that reads a wrapper the caller declares captures it.
				await captures.append(contentsOf: fillCaptures(
					of: hole,
					fill: child.generator,
					propertiesGeneratedLater: child.propertiesGeneratedLater,
					isSendable: child.generator.fillKey.map(sendableFillKeys.contains) ?? false,
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
	/// tree, walked inside each `@Sendable` stage of the fill, beside the fields each stage binds.
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
		for (stageIndex, fields) in hole.stages.enumerated() {
			if Self.fillStageIsSendable(hole: hole, stageIndex: stageIndex, isSendable: isSendable) {
				sendableBuilders.append(SendableBuilder(property: hole.property, declaringType: hole.ownerType, fillSeamType: hole.scopeSeamType))
			}
			for field in fields where boundLabels.contains(field.property.label) {
				fillDeclarationsByLabel[field.property.label] = [VisibleDeclaration(
					property: field.property,
					instanceProperty: field.property.asLazilyInstantiatedInstancePropertyOfDeclaredBinding,
					declaringType: field.declaringType,
					declarationLocation: field.declarationLocation,
					sendableBuilderDepth: sendableBuilders.count,
				)]
			}
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
	/// functions' parameters (see `CycleParameter`). Empty for nearly every scope.
	let cycleClosingRedeclaredLabels: [BuiltDeclaration: Set<String>]
	/// The parameters this scope's builder function needs, which the next pass of `Scope.createScopeGenerator` creates
	/// the tree with: the labels its tree receives from the scopes enclosing it that a scope between it and one of its
	/// cycle-closing scopes declares (see `CycleParameter.parameters`). Empty for nearly every scope.
	let foundCycleParameters: [CycleParameter]
	/// Whether a scope in this tree found other parameters for its builder function than it was created with, so that
	/// `Scope.createScopeGenerator` creates the tree again.
	let cycleParametersChangedInTree: Bool
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

	/// For a fill, the fields of its hole's struct it binds from the struct (see `fillStructBoundLabels`), in stage and
	/// field order. Empty for every other generator.
	nonisolated var fillBoundFields: [SeamSignature.Hole.Field] {
		guard let hole = fillHole else { return [] }
		return hole.stages.joined().filter { fillStructBoundLabels.contains($0.property.label) }
	}

	/// The fills of enclosing calls that calls in this subtree refer to by name, each by its key with its function's
	/// name, which no builder function declared between such a call and the fill may share (see `builderFunctionNames`).
	let referencedFillNamesByKey: [String: String]
	/// The keys of `referencedFillNamesByKey` referred to from inside a `@Sendable` builder function that does not
	/// enclose the fill, or passed to a seam that takes the fill `@Sendable`.
	let fillKeysReferencedFromSendableFunction: Set<String>
	/// For a seam call, the keys of its fills declared `@Sendable` beside those whose own hole is `@Sendable`: a
	/// `@Sendable` builder function that does not enclose the fill refers to it, or a call inside the fill passes it to a
	/// seam that takes it `@Sendable`.
	let sendableFillKeys: Set<String>
	/// The calls of a staged builder's stages made just before this scope's `@Sendable` builder function, each
	/// binding the stage it returns: empty but where the seam's tree builds a hole beneath that function.
	private let stageCalls: [String]
	/// See `MockParameterNode.stageCalls`.
	nonisolated var stageCallsBeforeBuilderFunction: [String] {
		stageCalls
	}

	/// Whether this scope's generated subtree holds a site of a hole of the seam whose tree is generated: such a
	/// child, a carrier, starts after its siblings that hold none (see `orderedPropertyToGenerateIndices`).
	let containsBuildSite: Bool
	/// The fields the scope structs of the sites in this generator's subtree carry: a fill the seam generates binds
	/// each of the filled seam's fields they carry, whether or not its own tree reads it.
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

	/// For a scope that calls another module's public mock: what the call passes each builder it fills, by label.
	nonisolated var holeArgumentValuesByLabel: [String: String] {
		var valuesByLabel = [String: String]()
		for holeCallArgument in holeCallArguments {
			valuesByLabel[holeCallArgument.label] = holeCallArgument.value
		}
		return valuesByLabel
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
		var siblingsByLabel = [String: [(property: Property, index: Int)]]()
		for sibling in siblings {
			siblingsByLabel[sibling.property.label, default: []].append((sibling.property, sibling.index))
		}
		var siblingDependencies = propertiesToGenerate.enumerated().map { scopeIndex, scope in
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
		for case let (index, aliasProperty?) in propertiesToGenerate.map(\.property).enumerated()
			where requiredOnlyIfAvailableAliasProperties.contains(aliasProperty)
		{
			guard let fulfillingProperty = propertiesToGenerate[index].onlyIfAvailableAliasFulfillingProperty else { continue }
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

		// Each sibling follows the siblings it depends upon, depth first in index order. The search keeps its own
		// path, since a scope can have as many children depending on one another in turn as the module has types.
		var orderedIndices = [Int]()
		// A seam call's fills declare no property, and each is generated.
		var unfulfilledIndices = Set(siblings.map(\.index)).union(propertiesToGenerate.indices.filter { propertiesToGenerate[$0].property == nil })
		// In a seam's tree, a child whose subtree holds a site of one of its holes – a carrier – starts last: first every
		// child that is no carrier and depends on none through the edges above, in index order, then the rest, in index
		// order. No edge is added or dropped, so every receive keeps the availability it has; the start order only puts
		// every sibling that can be built before a site there, so the site's scope struct carries it. Without a carrier
		// the order is the index order. A sibling that depends on a carrier and is declared after a later carrier is
		// built after that one, so a fill of the later carrier's site that reads it is reported, not supported
		// (`FillFinding.Kind.declarationBoundAfterSite`): a deliberate gap, which a finer order could close later.
		let startIndices: [Int] = if propertiesToGenerate.contains(where: \.containsBuildSite) {
			{
				let carrierIndices = propertiesToGenerate.indices.filter { propertiesToGenerate[$0].containsBuildSite }
				let reachesCarrier = propertiesToGenerate.indices.map { index in
					carrierIndices.contains { dependsOn($0, from: index) }
				}
				return propertiesToGenerate.indices.filter { !reachesCarrier[$0] } + propertiesToGenerate.indices.filter { reachesCarrier[$0] }
			}()
		} else {
			Array(propertiesToGenerate.indices)
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
					orderedIndices.append(index)
					path.removeLast()
				}
			}
		}
		return orderedIndices
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
	/// `builtType` for `builtProperty` receives from the scopes enclosing it – in the order a walk of the body meets
	/// them: the type's own dependencies, `ownDependencies`, then each of `children`'s trees, depth first, each scope's
	/// dependencies (and a cycle-closing scope's parameters, which it receives for the function it refers to, where that
	/// function's body first receives them) before its children's, all in declaration order. The order depends only on
	/// where the labels are received, never on how they or their types are named, so renaming a graph never reorders a
	/// function's parameters. Every label the body receives is met: a receive comes from a dependency of a type the walk
	/// visits, an alias among the dependencies of the type declaring it, which the walk visits first, or a cycle-closing
	/// scope's parameter.
	private static func inOrderTheBodyFirstReceives(
		ofLabels labels: Set<String>,
		builtProperty: Property,
		builtType: TypeDescription,
		ownDependencies: [Dependency],
		children: [ScopeGenerator],
	) -> [(label: String, receiver: CycleParameter.Receiver)] {
		var unmetLabels = labels
		var firstReceives = [(label: String, receiver: CycleParameter.Receiver)]()
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
			if unmetLabels.remove(label) != nil {
				firstReceives.append((label, receiver()))
			}
		}
		/// Meets the receives among `dependencies`, those of the type at `index` in `visitedTypes`.
		func meet(_ dependencies: [Dependency], ofTypeAt index: Int) {
			for dependency in dependencies {
				switch dependency.source {
				case .received:
					meet(dependency.property.label, receiver: .init(declarationLocation: dependency.declarationLocation, chain: chain(endingAt: index)))
				case let .aliased(fulfillingProperty, _, _):
					meet(fulfillingProperty.label, receiver: .init(declarationLocation: dependency.declarationLocation, chain: chain(endingAt: index)))
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
				meet(parameter.property.label, receiver: generator.property == builtProperty
					// This function's own parameter, whose receive this walk met where the scope was given the parameter: a
					// chain through the scope would grow with each pass that finds the parameters, which then never settle.
					? parameter.receiver
					: .init(declarationLocation: parameter.receiver.declarationLocation, chain: chain(endingAt: parentIndex) + parameter.receiver.chain))
			}
			generatorsToVisit.append(contentsOf: generator.propertiesToGenerate.reversed().map { (generator: $0, parentIndex: index) })
		}
		return firstReceives
	}

	/// Whether this scope declares a builder function a lazy cycle closes on that takes parameters (see `CycleParameter`).
	nonisolated private var declaresCycleParameters: Bool {
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
		declaresCycleParameters ? unavailableProperties.subtracting(cycleParameterProvidedForms) : unavailableProperties
	}

	/// The `propertiesGeneratedLater` of the scopes this scope's builder function builds, given those of this scope: the
	/// forms the function's parameters provide are bound inside it.
	nonisolated private func bodyPropertiesGeneratedLater(_ propertiesGeneratedLater: Set<Property>) -> Set<Property> {
		guard declaresCycleParameters, !propertiesGeneratedLater.isEmpty else { return propertiesGeneratedLater }
		return propertiesGeneratedLater.subtracting(cycleParameterProvidedForms.map(\.asUnwrappedProperty))
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
		var generatedProperties = [String]()
		for (index, child) in orderedChildren.enumerated() {
			try await generatedProperties.append(
				child.generator.generateCode(
					codeGeneration: codeGeneration,
					unavailableProperties: child.unavailableProperties,
					propertiesGeneratedLater: child.propertiesGeneratedLater,
					builderFunctionNames: childBuilderFunctionNames?[index].flatMap(\.self)
						?? BuilderFunctionNames(fillIsSendable: child.generator.fillKey.map(sendableFillKeys.contains) ?? false),
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
		/// For a fill, whether a `@Sendable` function that does not enclose it refers to it, so it is `@Sendable` too.
		var fillIsSendable = false
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
		var referencedDeclarations = Set<BuiltDeclaration>()
		for child in children where !child.cycleClosedOnDeclarations.isEmpty {
			referencedDeclarations.formUnion(child.cycleClosedOnDeclarations)
		}
		// A call inside a fill of its seam's call refers to the fill by name, as a cycle-closing scope refers to the
		// function it closes on, so no builder function between the two may share that name either.
		let referencedFunctionNames = Set(referencedDeclarations.map {
			enclosingFunctionNames[$0, default: functionName(toBuild: $0.property)]
		}).union(children.flatMap(\.referencedFillNames))
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
			let holeArgumentList = publicMockCall == nil ? holeCallArguments.map { "\($0.label.spelledAsArgumentLabel): \($0.value)" } : []
			let returnLineSansReturn = holeArgumentList.isEmpty
				? "\(instantiationDeclaration)(\(argumentList))"
				: "\(instantiationDeclaration)(\(([argumentList].filter { !$0.isEmpty } + holeArgumentList).joined(separator: ", ")))"
			// The stage calls of a staged builder whose next stage starts in this scope's `@Sendable` builder function,
			// made before the function is declared.
			let stageCallLines = stageCalls.map { "\($0)\n" }.joined()
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
				let forwardedPropertiesHaveLabels = forwardedProperties.count > 1
				let forwardedArguments = (
					forwardedProperties.map {
						if forwardedPropertiesHaveLabels {
							"\($0.label.spelledAsArgumentLabel): $0.\($0.label)"
						} else {
							"\($0.label.spelledAsArgumentLabel): $0"
						}
					} + cycleParameterArguments(unavailableProperties: unavailableProperties),
				).joined(separator: ", ")
				let generatedProperties = try await seamGuardLines + generateProperties(
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
					functionParameters.initializerFunctionParameters.map(\.description).joined()
				}
				// A cycle-closing scope declares no function: it refers to the enclosing one it closes on.
				let functionName = if isPropertyCycle {
					closedOnFunctionName(builtFor: property, enclosingFunctionNames: builderFunctionNames.enclosingFunctionNames)
				} else {
					builderFunctionNames.functionName ?? Self.functionName(toBuild: property)
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

				let typeDescription = property.typeDescription.asSource
				// A type constructed by annotation spells its generic arguments only in `propertyDeclaration`.
				let unwrappedTypeDescription = property
					.typeDescription
					.unwrapped
					.spelledForConstruction
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
				\(stageCallLines)\(functionDeclaration)\(propertyDeclaration) = \(instantiatorInstantiation)
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
					return "\(stageCallLines)let \(property.label) = \(lazilyInstantiatedInstantiation)"
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
				let functionArguments = functionParameters.isEmpty ? "" : functionParameters.initializerFunctionParameters.map(\.description).joined()

				return """
				\(stageCallLines)\(functionDecorator)func \(functionName)(\(functionArguments)) -> \(concreteTypeName) {
				\(generatedProperties.joined(separator: "\n"))
				\(Self.standardIndent)\(generatedProperties.isEmpty ? "" : "return ")\(returnLineSansReturn)\(constructionLineEnd)
				}
				let \(property.label) = \(lazilyInstantiatedInstantiation)
				"""
			case .constant:
				let callArguments = cycleParameterArguments(unavailableProperties: unavailableProperties).joined(separator: ", ")
				guard !isPropertyCycle else {
					// A scope that closes a cycle declares no function: it calls the function of the declaration it repeats
					// with that function's cycle parameters, typed as a constant with content is. A closer builds nothing, so
					// it holds no seam's site and `stageCallLines` is empty, as it is for every closer.
					let call = "\(closedOnFunctionName(builtFor: property, enclosingFunctionNames: builderFunctionNames.enclosingFunctionNames))(\(callArguments))"
					return if erasedToConcreteExistential {
						"\(stageCallLines)let \(property.label) = \(property.typeDescription.asSource)(\(call))\n"
					} else {
						"\(stageCallLines)let \(property.asSource) = \(call)\n"
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
				let functionArguments = functionParameters.isEmpty ? "" : functionParameters.initializerFunctionParameters.map(\.description).joined()

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

				return "\(functionDeclaration)\(propertyDeclaration) = \(initializer)\n"
			}
		case let .hole(property, _, site):
			// A tree built only to compute the seam's signature has no site, and generates nothing.
			guard let site else { return "" }
			return Self.buildSiteCode(of: property, at: site)
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

	/// The declaration of `hole`'s scope type, nested in the seam: one struct of the values in scope at the site, or,
	/// for a staged builder, an enum holding one struct per stage. Spelled `public`, as the guard enum is, so its
	/// access is the seam's; each field at its own access. A field bound from a deferred parameter holds the seam's
	/// memo of it and reads the memo's instance when it is read, so a fill creates the value when it uses it, as inline;
	/// its struct then declares the initializer the seam's tree calls, which takes the memo under the field's label.
	static func scopeTypeDeclaration(of hole: SeamSignature.Hole) -> String {
		func structDeclaration(named name: String, fields: [SeamSignature.Hole.Field], indent: String) -> String {
			guard !fields.isEmpty else { return "\(indent)public struct \(name) {}" }
			let memberIndent = "\(indent)\(standardIndent)"
			let fieldDeclarations = fields.map { field in
				if field.isDeferredParameter {
					"\(memberIndent)\(field.access.spelledOnGeneratedDeclaration) var \(field.property.asSource) { \(field.memoName).\(Dependency.lazilyInstantiatedInstancePropertyName) }"
				} else {
					"\(memberIndent)\(field.access.spelledOnGeneratedDeclaration) let \(field.property.asSource)"
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
				"\(field.property.label.spelledAsArgumentLabel): \((field.memoType ?? field.property.typeDescription).asSource)"
			}
			let initializerAssignments = fields.map { field in
				if field.isDeferredParameter {
					"\(memberIndent)\(standardIndent)\(field.memoName) = \(field.property.label)"
				} else {
					"\(memberIndent)\(standardIndent)self.\(field.property.label) = \(field.property.label)"
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
		guard hole.stages.count > 1 else {
			return structDeclaration(named: hole.scopeTypeName, fields: hole.stages.first ?? [], indent: standardIndent)
		}
		let stageStructs = hole.stages.enumerated().map { stageIndex, fields in
			structDeclaration(named: SeamSignature.Hole.stageName(at: stageIndex), fields: fields, indent: standardIndent + standardIndent)
		}
		return """
		\(standardIndent)public enum \(hole.scopeTypeName) {
		\(stageStructs.joined(separator: "\n\n"))
		\(standardIndent)}
		"""
	}

	/// The binding a seam's tree makes at a site of `property`, a hole: the builder's last stage called with the
	/// values in scope there. A constant is bound with its declared type, as inline binds an existential; a wrapper,
	/// which the builder returns, without one.
	static func buildSiteCode(of property: Property, at site: SeamSignature.Hole) -> String {
		let lastStageIndex = site.stages.count - 1
		let stageFunction = lastStageIndex == 0 ? site.internalName : "\(site.internalName)_\(SeamSignature.Hole.stageName(at: lastStageIndex))"
		let arguments = site.stages[lastStageIndex].map { "\($0.property.label.spelledAsArgumentLabel): \($0.property.label)" }.joined(separator: ", ")
		let declaration = property.propertyType.isConstant ? "let \(property.asSource)" : "let \(property.label)"
		return "\(declaration) = \(stageFunction)(\(site.stageStructType(at: lastStageIndex, qualifiedBy: nil).asSource)(\(arguments)))"
	}

	/// The function a seam's caller generates to fill the builder for `hole`: it binds the fields of each stage's
	/// struct that the tree of its one child, the hole's property, reads, returns each later stage as a `@Sendable`
	/// function, and builds the property in the last, as inline builds it at the site.
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
		// is generated in – carries it in its own struct, unless the fill reads it from the caller's scope: one bound
		// from a deferred parameter (see `fillStructBoundLabels`).
		func isRead(_ field: SeamSignature.Hole.Field) -> Bool {
			fillStructBoundLabels.contains(field.property.label)
				&& (child.reads(field.property) || child.fieldsCarriedBySites.contains(field.property))
		}
		let lastStageIndex = hole.stages.count - 1
		let childCode = try await generateProperties(
			codeGeneration: codeGeneration,
			propertiesGeneratedLater: propertiesGeneratedLater,
			enclosingFunctionNames: enclosingFunctionNames,
			leadingMemberWhitespace: String(repeating: Self.standardIndent, count: lastStageIndex + 1),
		)
		// Built from the innermost stage out, each stage's function nested in the one before it.
		var body = childCode.joined(separator: "\n").split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
		body.append(String(repeating: Self.standardIndent, count: lastStageIndex + 1) + "return \(property.label)")
		for stageIndex in stride(from: lastStageIndex, through: 0, by: -1) {
			let indent = String(repeating: Self.standardIndent, count: stageIndex + 1)
			let bindings = hole.stages[stageIndex].filter(isRead).map { "\(indent)let \($0.property.label) = scope.\($0.property.label.spelledAsArgumentLabel)" }
			let stageFunctionName = stageIndex == 0 ? functionName : "\(functionName)_\(SeamSignature.Hole.stageName(at: stageIndex))"
			let returnType = stageIndex == lastStageIndex
				? hole.property.typeDescription
				: TypeDescription.attributed(hole.stageFunctionType(at: stageIndex + 1, qualifiedBy: hole.scopeSeamType), specifiers: [], attributes: ["Sendable"])
			let decorator = Self.fillStageIsSendable(hole: hole, stageIndex: stageIndex, isSendable: isSendable) ? "@Sendable " : ""
			let outerIndent = String(repeating: Self.standardIndent, count: stageIndex)
			body = ["\(outerIndent)\(decorator)func \(stageFunctionName)(_ scope: \(hole.stageStructType(at: stageIndex, qualifiedBy: hole.scopeSeamType).asSource)) -> \(returnType.asSource) {"]
				+ bindings
				+ body
				+ ["\(outerIndent)}"]
			if stageIndex > 0 {
				let enclosingIndent = String(repeating: Self.standardIndent, count: stageIndex)
				body.append("\(enclosingIndent)return \(stageFunctionName)")
			}
		}
		return body.joined(separator: "\n")
	}

	/// Whether the function of the stage at `stageIndex` of a fill for `hole` is `@Sendable`: every stage after the first,
	/// which an earlier stage returns as a `@Sendable` function, and the first when a `@Sendable` function that does not
	/// enclose the fill refers to it (`isSendable`) or the seam takes the builder `@Sendable`. A fill's tree is built in
	/// its last stage, so a read in it is inside a `@Sendable` function exactly when that stage is one.
	static func fillStageIsSendable(hole: SeamSignature.Hole, stageIndex: Int, isSendable: Bool) -> Bool {
		stageIndex > 0 || isSendable || hole.isSendable
	}

	/// The initializers a seam's module generates for the seam, one per tier of its signature, followed by the enum
	/// every generated call refers to. Each tier but the narrowest passes `nil` for the parameters it omits and calls
	/// the next narrower tier; the narrowest builds the tree and calls the seam's own initializer.
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
		// Every tier carries the attributes a root's generated `init()` carries: a caller can reach any tier, and a
		// wider tier calls the next narrower one.
		let attributesPrefix = instantiable.generatedInitializerAttributes.isEmpty ? "" : "\(instantiable.generatedInitializerAttributes) "
		// Every tier takes every builder, after its parameters: a hole is required.
		let builderParameters = signature.holes.map { hole in
			"\(hole.builderLabel.spelledAsArgumentLabel) \(hole.internalName): \(hole.builderType(qualifiedBy: hole.innerSeamType == nil ? nil : hole.scopeSeamType).asSource)"
		}
		let builderArguments = signature.holes.map { "\($0.builderLabel.spelledAsArgumentLabel): \($0.internalName)" }
		// No parameter has a default: every call writes every argument, so a hand-written call fails to compile when the
		// tree comes to take another parameter, rather than passing `nil` for it.
		func parameterList(of parameters: [SeamSignature.Parameter]) -> String {
			(parameters.map(\.generatedSpelling) + builderParameters).joined(separator: ", ")
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
				// The narrowest tier builds the tree.
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
				let arguments = (tierParameters[index + 1]
					.map { parameter in
						let value = if !tierParameterSet.contains(parameter.property) {
							"nil"
						} else if parameter.isDeferred {
							"\(parameter.internalName)()"
						} else {
							parameter.property.label
						}
						return "\(parameter.property.label.spelledAsArgumentLabel): \(value)"
					}
					+ builderArguments)
					.joined(separator: ", ")
				body = "\(bodyIndent)self.init(\(arguments))"
			}
			let marker = tier == .public
				? seamRoot.unreadTypeComment?.markerLine(namedBy: parameters.map(\.property.typeDescription) + signature.holes.map(\.property.typeDescription), indent: Self.standardIndent).map { "\($0)\n" }
				: nil
			initializers.append("""
			\(marker ?? "")\(Self.standardIndent)\(attributesPrefix)\(tier.spelledOnGeneratedDeclaration) \(initializerKeyword)(\(parameterList(of: parameters))) {
			\(body)
			\(Self.standardIndent)}
			""")
		}
		// The scope struct of each site of the seam's own tree, in hole order, before the initializers that build them.
		// Each `public` declaration that names a type SafeDI reads no declaration of is marked for the file's comment:
		// a scope struct by its `public` fields, a tier by its parameters and the types its builders return.
		let scopeTypes = signature.holes.filter { $0.innerSeamType == nil }.map { hole in
			let declaration = Self.scopeTypeDeclaration(of: hole)
			guard let marker = seamRoot.unreadTypeComment?.markerLine(namedBy: hole.stages.flatMap { $0.filter { $0.access == .public }.map(\.property.typeDescription) }, indent: Self.standardIndent) else { return declaration }
			return "\(marker)\n\(declaration)"
		}
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
		// The instance of a `LazilyInstantiated` beside a forwarded property is named after
		// its `LazilyInstantiated`, and is only ever read by the wrapper bound below, so a
		// receive of the forwarded property is not passed it.
		let flatReceivedNames = Self.namesApart(
			preferredNames: parameters.flatReceivedProperties.map(\.label),
			typeDescriptions: parameters.flatReceivedProperties.map { property in
				parameters.lazilyInstantiatedPropertyByInstanceBesideForwardedProperty[property]?.typeDescription ?? property.typeDescription
			},
			namesInScope: Set(otherFlatLabels).union(treeBindingNames),
			reservedNames: namesDeclaredInBuilderFunctions,
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
			MockRootParameters.UncoveredParameter(
				property: uncoveredDependencies.properties[index],
				label: uncoveredDependencyNames[index],
				typeSource: uncoveredDependencies.typeSources[index],
				instantiatedType: uncoveredDependencies.instantiatedTypes[index],
				isSendableAutoclosure: uncoveredDependencies.indicesInstantiatedInSendableFunction.contains(index),
				creatingTypes: creatingTypesByProperty[uncoveredDependencies.properties[index]] ?? [],
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
			(
				label: name,
				typeSource: sendablePassedUpBuilders.contains(property)
					? TypeDescription.attributed(property.typeDescription, specifiers: [], attributes: ["escaping", "Sendable"]).asSource
					: property.typeDescription.asFunctionParameter.asSource,
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
		if let publicMockPlan, !publicMockPlan.holes.isEmpty {
			// The scope struct of each hole's site, which the builder `mock()` takes is handed.
			for hole in publicMockPlan.holes {
				if let marker = unreadTypeComment?.markerLine(namedBy: hole.stages.flatMap { $0.filter { $0.access == .public }.map(\.property.typeDescription) }, indent: indent) {
					lines.append(marker)
				}
				lines.append(Self.scopeTypeDeclaration(of: hole))
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
			let typeSource = dependency.property.typeDescription.asFunctionParameter.asSource
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
		/// In a public mock's tree, the calls of the stages of staged builders whose next stage starts in this node's
		/// `@Sendable` builder function, made before the function is declared (`SeamHoles.stageCalls(at:)`).
		let stageCalls: [String]
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
		var builderParameterTypes: [TypeDescription] {
			callSiteArguments.map { argument in
				(argument.typeDescription.strippingEscaping.autoclosureValueType ?? argument.typeDescription).asFunctionParameter
			}
		}

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
			let dependencyInnerLabels = Set(dependencies.map(\.property.label))
			return callSiteArguments.filter { argument in
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
		}

		deinit {
			var items = [MockTreeItem]()
			swap(&items, &self.items)
			DeferredRelease.release(consume items)
		}

		/// Mutated only by `deinit`, which has the only access.
		nonisolated(unsafe) private(set) var items: [MockTreeItem]
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
					fulfillingTypeDescription: site.builderType(qualifiedBy: nil),
					fulfillingPropertyIsLazilyInstantiatedInstance: false,
					declarationReference: nil,
					holeSite: site,
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
				let childConstructionUnavailableProperties = await childGenerator.bodyUnavailableProperties(childUnavailableProperties)

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
					stageCalls: childGenerator.stageCallsBeforeBuilderFunction,
					fillingGenerator: childGenerator.holeArgumentValuesByLabel.isEmpty ? nil : childGenerator,
					holeArgumentValuesByLabel: childGenerator.holeArgumentValuesByLabel,
					fillPropertiesGeneratedLater: childBodyPropertiesGeneratedLater,
					referencedFillNames: Set(childGenerator.referencedFillNamesByKey.values),
					forwardedProperties: forwardedProperties,
					isPropertyCycle: isPropertyCycle,
					closedOnDeclaration: childGenerator.closedOnDeclaration,
					cycleClosedOnDeclarations: childGenerator.cycleClosedOnDeclarations,
					isReferencedByCycleClosingScope: childGenerator.isReferencedByCycleClosingScope,
					cycleParameters: childGenerator.cycleParameters,
					cycleParameterArgumentUnavailableProperties: Set(childGenerator.cycleParameters.map(\.property)).intersection(childUnavailableProperties),
					callSiteLazilyInstantiatedInstanceProperties: childGenerator.callSiteLazilyInstantiatedInstanceProperties,
					buildsInSendableFunction: childGenerator.buildsInSendableFunction,
					requiresSendable: childInsideSendable,
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
		instantiable.dependencies.filter { dependency in
			switch dependency.source {
			case .instantiated:
				!holeSiteProperties.contains(dependency.property) && !treePropertyNodes.contains(where: {
					$0.property == dependency.property || $0.property.asLazilyInstantiatedInstanceProperty == dependency.property
				})
			case .received, .aliased, .forwarded:
				false
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

		// Emit stored properties.
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
	final class SendableOverrideExtractor {
		init(functionName: String) {
			self.functionName = functionName
		}

		/// Records that `expression` is read into a local named after the
		/// outermost `@Sendable` function, and returns that local's name.
		func extract(_ expression: String, localNameSuffix: String) -> String {
			let localName = "\(functionName)__\(localNameSuffix)".spelledAsJoinedIdentifier
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
		let builderFunctionNamesByNode = propertyNodes.contains(where: { !$0.cycleClosedOnDeclarations.isEmpty || $0.isReferencedByCycleClosingScope })
			? builderFunctionNames(
				for: propertyNodes.map { node in
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
		mergeSiblingDisambiguations(into: &combinedDisambiguationMap, for: propertyNodes, labelMap: labelMap)

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
				let functionName = if node.isPropertyCycle {
					node.closedOnDeclaration.flatMap { builderFunctionNames.enclosingFunctionNames[$0] } ?? Self.functionName(toBuild: node.property)
				} else {
					builderFunctionNames.functionName ?? Self.functionName(toBuildPropertyNamed: disambiguated)
				}

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
					await lines.append(contentsOf: generateInstantiatorBinding(
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
					))
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
					let functionArguments = functionParameters.isEmpty ? "" : functionParameters.initializerFunctionParameters.map(\.description).joined()
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
						SendableOverrideExtractor(functionName: functionName)
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
					for extraction in startedSendableOverrideExtractor?.extractions ?? [] {
						lines.append("\(indent)let \(extraction.localName) = \(extraction.expression)")
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
		if let holeSite = alias.holeSite {
			return "\(indent)\(buildSiteCode(of: alias.property, at: holeSite))"
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
	) async -> [String] {
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
			functionParameters.initializerFunctionParameters.map(\.description).joined()
		}

		// Build the forwarded arguments for the Instantiator closure call, followed by the bindings in scope here of the
		// labels the function a lazy cycle closes on takes.
		let forwardedPropertiesHaveLabels = forwardedProperties.count > 1
		let forwardedArguments = (
			forwardedProperties.map {
				if forwardedPropertiesHaveLabels {
					"\($0.label.spelledAsArgumentLabel): $0.\($0.label)"
				} else {
					"\($0.label.spelledAsArgumentLabel): $0"
				}
			} + mockCycleParameterArguments(
				for: node,
				flatParameterDisambiguationMap: flatParameterDisambiguationMap,
				lazilyInstantiatedBindingNames: lazilyInstantiatedBindingNames,
			),
		).joined(separator: ", ")

		let functionDecorator = if node.buildsInSendableFunction {
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
			let startedSendableOverrideExtractor: SendableOverrideExtractor? = if sendableOverrideExtractor == nil, node.buildsInSendableFunction {
				SendableOverrideExtractor(functionName: functionName)
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
				for extraction in startedSendableOverrideExtractor.extractions {
					lines.append("\(indent)let \(extraction.localName) = \(extraction.expression)")
				}
			} else {
				functionOverrideExpression = overrideExpression
				// The caller read them for the construction inside this function, through the extractor of an enclosing
				// `@Sendable` function if any.
				functionConstructionArguments = arguments
			}

			let functionReturnType = node.instantiatedTypeDescription.asSource
			// The stage calls of a public mock's staged builders whose next stage starts in this function, made before it.
			for stageCall in node.stageCalls {
				lines.append("\(indent)\(stageCall)")
			}
			lines.append("\(indent)\(functionDecorator)func \(functionName)(\(functionArguments)) -> \(functionReturnType) {")
			let preamble = await callPreamble(of: node, indent: innerIndent)
			lines.append(contentsOf: preamble)
			lines.append(contentsOf: receiverBindings)
			lines.append(contentsOf: sendableAutoclosureBindings)
			lines.append(contentsOf: childBindings)

			// Swift's implicit-return rule only applies when the function
			// body is a single expression. Fills, receiver bindings, autoclosure
			// bindings, and child bindings all add extra statements, so any
			// one forces an explicit `return`. The function's return type
			// gives both branches of an `if` expression a contextual type.
			let returnKeyword = preamble.isEmpty && childBindings.isEmpty && receiverBindings.isEmpty && sendableAutoclosureBindings.isEmpty ? "" : "return "
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
			lines.append("\(innerIndent)\(returnKeyword)\(constructionExpression)")
			lines.append("\(indent)}")
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
		} else if forwardedArguments.isEmpty {
			"\(unwrappedTypeDescription)(\(functionName))"
		} else {
			"""
			\(unwrappedTypeDescription) {
			\(indent)\(standardIndent)\(functionName)(\(forwardedArguments))
			\(indent)}
			"""
		}

		if let promotedParameterName, !node.property.propertyType.isLazilyInstantiated {
			// A public mock takes an instantiator it builds for a received dependency as itself.
			lines.append("\(indent)let \(outerBinding) = \(passing(promotedParameterName, orBuilding: instantiatorConstruction))")
		} else {
			lines.append("\(indent)let \(outerBinding) = \(instantiatorConstruction)")
		}

		return lines
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
	/// The holes of every site in the tree of these items, one per builder, in builder-label order.
	var holesOfTree: [SeamSignature.Hole] {
		var holesByBuilderLabel = [String: SeamSignature.Hole]()
		// A stack of its own, since a mock tree can be as deep as the module has types.
		var itemsToVisit = self
		while let item = itemsToVisit.popLast() {
			switch item {
			case let .alias(alias):
				if let holeSite = alias.holeSite {
					holesByBuilderLabel[holeSite.builderLabel] = holeSite
				}
			case let .property(node):
				itemsToVisit.append(contentsOf: node.children)
			}
		}
		return holesByBuilderLabel.values.sorted { $0.builderLabel < $1.builderLabel }
	}

	/// The builders of the holes of other modules' public mocks that the calls in the tree of these items pass up, as
	/// the calling tree receives them, with each one's hole.
	var passedUpHolesByBuilder: [Property: SeamSignature.Hole] {
		var holesByBuilder = [Property: SeamSignature.Hole]()
		// A stack of its own, since a mock tree can be as deep as the module has types.
		var nodesToVisit = propertyNodes
		while let node = nodesToVisit.popLast() {
			if let publicMockCall = node.publicMockCall {
				let filledSites = Set(publicMockCall.filledHoles.map(\.site))
				for parameter in publicMockCall.passedParameters {
					if let hole = parameter.hole, !filledSites.contains(hole.site) {
						holesByBuilder[parameter.dependency.property] = hole
					}
				}
			}
			nodesToVisit.append(contentsOf: node.propertyChildren)
		}
		return holesByBuilder
	}

	/// The builders among `passedUpHolesByBuilder` that a call made in a `@Sendable` builder function passes up, which
	/// the function captures.
	var passedUpBuildersCapturedBySendableFunctions: Set<Property> {
		var builders = Set<Property>()
		// A stack of its own, since a mock tree can be as deep as the module has types.
		var nodesToVisit = propertyNodes
		while let node = nodesToVisit.popLast() {
			if node.requiresSendable, let publicMockCall = node.publicMockCall {
				let filledSites = Set(publicMockCall.filledHoles.map(\.site))
				for parameter in publicMockCall.passedParameters {
					if let hole = parameter.hole, !filledSites.contains(hole.site) {
						builders.insert(parameter.dependency.property)
					}
				}
			}
			nodesToVisit.append(contentsOf: node.propertyChildren)
		}
		return builders
	}

	/// The generators of the calls of other modules' public mocks in the tree of these items that fill builders
	/// (`ScopeGenerator.MockParameterNode.fillingGenerator`), each with the `propertiesGeneratedLater` its node generates
	/// the fills with (`ScopeGenerator.MockParameterNode.fillPropertiesGeneratedLater`).
	var fillingGenerators: [(generator: ScopeGenerator, propertiesGeneratedLater: Set<Property>)] {
		var fillingGenerators = [(generator: ScopeGenerator, propertiesGeneratedLater: Set<Property>)]()
		// A stack of its own, since a mock tree can be as deep as the module has types.
		var nodesToVisit = propertyNodes
		while let node = nodesToVisit.popLast() {
			if let fillingGenerator = node.fillingGenerator {
				fillingGenerators.append((fillingGenerator, node.fillPropertiesGeneratedLater))
			}
			nodesToVisit.append(contentsOf: node.propertyChildren)
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
