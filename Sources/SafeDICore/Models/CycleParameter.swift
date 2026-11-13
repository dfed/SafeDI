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

/// A parameter of the builder function of a scope that a lazy cycle closes on: a label the function's body receives
/// from the scopes enclosing it that a scope between it and one of its cycle-closing scopes declares again.
///
/// A cycle-closing scope builds nothing: it refers to the builder function of the enclosing scope with its property
/// (see `ScopeGenerator`'s `isPropertyCycle`). That function would capture the declarations in scope where it is
/// declared, above the cycle, while the type a cycle-closing scope builds receives each label from the nearest
/// declaration on its own path, as every other `@Received` property does. So the function takes such a label as a
/// parameter, the scope that declares the function passes the binding in scope there, and each cycle-closing scope
/// passes its own nearest declaration: the property, its instance, or `nil` where it is unavailable.
struct CycleParameter: Hashable, Sendable {
	/// A receive of a parameter's label in the function's body.
	struct Receiver: Hashable, Sendable {
		/// The property received: the fulfilling property for an aliased dependency, the declared property otherwise.
		let property: Property
		/// Where the receiving dependency is declared.
		let declarationLocation: Dependency.DeclarationLocation?
		/// The types from the type the function builds to the receiving type, both included.
		let chain: [TypeDescription]
	}

	/// The property the parameter binds: the form of the label that provides every other form the function's body
	/// receives, made optional when no receiver requires it, since a scope that calls the function may then have
	/// nothing to pass.
	let property: Property
	/// The forms of the label that the function's body receives from the scopes enclosing it.
	let receivedForms: Set<Property>
	/// Those of `receivedForms` that some receiver requires (see `ScopeGenerator.requiredReceivedProperties`).
	let requiredForms: Set<Property>
	/// Those of `receivedForms` that some receiver requires through an `onlyIfAvailable` alias (see
	/// `ScopeGenerator.requiredAliasFulfillingProperties`). They order the scopes that declare the label where a
	/// cycle-closing scope's function is called, but require nothing of them: the alias is `nil` where the label's nearest
	/// declaration is unavailable.
	let requiredAliasFulfillingForms: Set<Property>
	/// The unwrapped forms of the label that every receiver receives only if available (see
	/// `ScopeGenerator.onlyIfAvailableUnwrappedReceivedProperties`).
	let onlyIfAvailableUnwrappedForms: Set<Property>
	/// The first receive of the label a walk of the function's body meets (see
	/// `ScopeGenerator.inOrderTheBodyFirstReceives`), which a diagnostic about what a cycle-closing scope passes the
	/// parameter is reported at.
	let receiver: Receiver
	/// The declaration of the parameter's label between the scope that declares the function and one of its
	/// cycle-closing scopes that precedes the others in source order, which a diagnostic about the label notes.
	let redeclaration: Redeclaration

	/// Whether every scope that calls the function passes a value: a receiver in its body requires the label.
	var isRequired: Bool {
		!requiredForms.isEmpty
	}

	/// The forms the parameter provides to the function's body: its property, the optional form of a non-optional
	/// one, and the instance of a non-optional lazily instantiated one, as `ScopeGenerator.provides` decides for a
	/// declaration. A parameter made optional also provides the non-optional form it was made from, which the
	/// function's body reads as a value that may be `nil`, as a seam's tree reads an optional parameter.
	var providedForms: Set<Property> {
		Self.forms(providedBy: property, receivedForms: receivedForms)
	}

	/// The forms a parameter of `property` provides to a function's body that receives `receivedForms` of its label: those
	/// a declaration of `property` provides, and, for an optional one, the non-optional form it is made from where the
	/// body receives it.
	private static func forms(providedBy property: Property, receivedForms: Set<Property>) -> Set<Property> {
		var providedForms = forms(providedBy: property)
		if case let .optional(unwrapped) = property.typeDescription, receivedForms.contains(Property(label: property.label, typeDescription: unwrapped)) {
			providedForms.insert(property.asUnwrappedProperty)
		}
		return providedForms
	}

	/// The forms a declaration of `property` provides to the scopes beneath it.
	static func forms(providedBy property: Property) -> Set<Property> {
		var forms: Set<Property> = [property]
		if !property.typeDescription.isOptional {
			forms.insert(property.asOptionalProperty)
		}
		if let instanceProperty = property.asLazilyInstantiatedInstancePropertyOfDeclaredBinding {
			forms.insert(instanceProperty)
			forms.insert(instanceProperty.asOptionalProperty)
		}
		return forms
	}

	/// The parameters of the builder function of a scope whose tree receives `receivedProperties` from the scopes
	/// enclosing it, for each label of `firstReceives` – those a scope between it and one of its cycle-closing scopes
	/// declares that the tree receives, each with its first receive and that declaration – in that order, and the labels
	/// among them that no one parameter can pass.
	///
	/// A parameter takes the form of its label that provides every other form the tree receives: a declaration of that
	/// form does, so each scope that calls the function passes one value. Where a receiver requires the label, the
	/// parameter takes the required form that provides every other required form, which each call's nearest declaration
	/// provides, as validation has checked. A form received only if available that it does not provide is passed `nil` in
	/// the function's body, as it is beneath any declaration that does not provide it, where no declaration that provides
	/// the required forms could provide it too: such as `x: Y?` or `x: Instantiator<X>?` beside a required `x: X`. One
	/// that such a declaration could provide – `x: LazilyInstantiated<X>?` beside a required `x: X` – would be handed a
	/// value by a call whose nearest declaration provides it, which the parameter cannot carry, so the label is
	/// unpassable. The parameter cannot tell which declarations its calls see, so a call whose nearest declaration
	/// provides only the required form, where `nil` would be right, is rejected too. Where every form is received only if
	/// available and no one parameter provides them all – such as `x: X?` and `x: Instantiator<X>?` – the label is
	/// unpassable as well. `DependencyTreeGenerator` reports an unpassable label (see `UnpassableCycleLabel`).
	static func parameters(
		firstReceives: [(label: String, receiver: Receiver, redeclaration: Redeclaration)],
		receivedProperties: Set<Property>,
		requiredReceivedProperties: Set<Property>,
		requiredAliasFulfillingProperties: Set<Property>,
		onlyIfAvailableUnwrappedReceivedProperties: Set<Property>,
		builtType: TypeDescription,
	) -> (parameters: [CycleParameter], unpassableLabels: [UnpassableCycleLabel]) {
		let labels = Set(firstReceives.map(\.label))
		var formsByLabel = [String: Set<Property>]()
		for receivedProperty in receivedProperties where labels.contains(receivedProperty.label) {
			formsByLabel[receivedProperty.label, default: []].insert(receivedProperty)
		}
		var parameters = [CycleParameter]()
		var unpassableLabels = [UnpassableCycleLabel]()
		for (label, receiver, redeclaration) in firstReceives {
			let forms = formsByLabel[label, default: []]
			let requiredForms = forms.intersection(requiredReceivedProperties)
			// The forms the parameter must provide: those a receiver requires, or every form where none is required.
			let formsToProvide = requiredForms.isEmpty ? forms : requiredForms
			// A parameter no receiver requires is made optional, since a scope that calls the function may then have nothing
			// to pass.
			let property = formsToProvide.sorted()
				.first { formsToProvide.isSubset(of: Self.forms(providedBy: $0)) }
				.map { requiredForms.isEmpty && !$0.typeDescription.isOptional ? $0.asOptionalProperty : $0 }
			let passedForms = property.map { forms.intersection(Self.forms(providedBy: $0, receivedForms: forms)) } ?? []
			let unpassedForms = forms.subtracting(passedForms)
			let passesEveryFormACallCanProvide = if requiredForms.isEmpty {
				// An optional wrapper offers no instance, so a parameter made optional can provide fewer forms than the form
				// it was made from.
				unpassedForms.isEmpty
			} else {
				// A form is passed `nil` only where no declaration that provides the required forms could provide it too.
				!unpassedForms.contains { requiredForms.isSubset(of: Self.forms(providedBy: $0.asUnwrappedProperty)) }
			}
			guard let property, passesEveryFormACallCanProvide else {
				unpassableLabels.append(UnpassableCycleLabel(builtType: builtType, receiver: receiver, forms: forms.sorted(), redeclaration: redeclaration))
				continue
			}
			parameters.append(CycleParameter(
				property: property,
				receivedForms: passedForms,
				requiredForms: requiredForms,
				requiredAliasFulfillingForms: passedForms.intersection(requiredAliasFulfillingProperties),
				onlyIfAvailableUnwrappedForms: Set(passedForms.map(\.asUnwrappedProperty)).intersection(onlyIfAvailableUnwrappedReceivedProperties),
				receiver: receiver,
				redeclaration: redeclaration,
			))
		}
		return (parameters, unpassableLabels)
	}
}

extension CycleParameter {
	/// A declaration of a label between the scope a lazy cycle closes on and one of its cycle-closing scopes, which the
	/// tree that cycle-closing scope builds again reads in place of the declarations above the function it closes on.
	struct Redeclaration: Hashable, Sendable {
		/// The declared property.
		let property: Property
		/// The type that declares it.
		let declaringType: TypeDescription
		/// Where it is declared, or `nil` for a declaration no `@Instantiable` type spells.
		let declarationLocation: Dependency.DeclarationLocation?

		/// The one of `self` and `other` that comes first in source order, then in property order, so that which of several
		/// declarations a diagnostic notes never depends on the order a walk met them in.
		func preceding(_ other: Redeclaration) -> Redeclaration {
			if declarationLocation == other.declarationLocation {
				(other.property, other.declaringType) < (property, declaringType) ? other : self
			} else {
				Dependency.DeclarationLocation.precedesInSourceOrder(declarationLocation, other.declarationLocation) ? self : other
			}
		}
	}
}

/// A label the body of the builder function a lazy cycle closes on receives from the scopes enclosing the function, which
/// a scope between the function and one of its cycle-closing scopes declares again, in forms no one parameter can pass:
/// a form a receiver requires beside one the parameter cannot carry that a declaration providing it could provide too,
/// or, where no receiver requires one, forms no one parameter provides together (see `CycleParameter.parameters`). The
/// type a cycle-closing scope builds again would read the label from above the function instead of from its nearest
/// declaration, so SafeDITool reports it.
struct UnpassableCycleLabel: Hashable, Sendable {
	/// The type the function builds.
	let builtType: TypeDescription
	/// The first receive of the label in the function's body.
	let receiver: CycleParameter.Receiver
	/// The forms of the label the function's body receives, in property order.
	let forms: [Property]
	/// The declaration of the label between the function and one of its cycle-closing scopes.
	let redeclaration: CycleParameter.Redeclaration
}

/// The parameters of the builder function a lazy cycle closes on, as the scopes beneath the function see them while
/// their generators are created. Each scope judges what it passes them against the nearest declaration of their labels
/// (see `NearestDeclarations`).
struct CycleParameterContext: Sendable {
	/// The function's parameters.
	let parameters: [CycleParameter]
}
