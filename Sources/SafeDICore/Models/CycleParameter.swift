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

	/// Whether every scope that calls the function passes a value: a receiver in its body requires the label.
	var isRequired: Bool {
		!requiredForms.isEmpty
	}

	/// The forms the parameter provides to the function's body: its property, the optional form of a non-optional
	/// one, and the instance of a non-optional lazily instantiated one, as `ScopeGenerator.provides` decides for a
	/// declaration. A parameter made optional also provides the non-optional form it was made from, which the
	/// function's body reads as a value that may be `nil`, as a seam's tree reads an optional parameter.
	var providedForms: Set<Property> {
		var providedForms = Self.forms(providedBy: property)
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
	/// declares that the tree receives, each with its first receive – in that order.
	///
	/// A label is a parameter only when one form the tree receives provides every other: a declaration of that form
	/// does, so each scope that calls the function passes one value. A label received in forms no one declaration
	/// provides – such as `x: X?` and `x: Instantiator<X>?`, each received only if available – is not a parameter, and
	/// the function's body reads it from the scopes enclosing the function, as it does a label no scope between
	/// declares again.
	static func parameters(
		firstReceives: [(label: String, receiver: Receiver)],
		receivedProperties: Set<Property>,
		requiredReceivedProperties: Set<Property>,
		requiredAliasFulfillingProperties: Set<Property>,
		onlyIfAvailableUnwrappedReceivedProperties: Set<Property>,
	) -> [CycleParameter] {
		let labels = Set(firstReceives.map(\.label))
		var formsByLabel = [String: Set<Property>]()
		for receivedProperty in receivedProperties where labels.contains(receivedProperty.label) {
			formsByLabel[receivedProperty.label, default: []].insert(receivedProperty)
		}
		return firstReceives.compactMap { label, receiver in
			let forms = formsByLabel[label, default: []]
			// A label received in forms no one declaration provides is left out: a deliberate gap (see above).
			let providingForm = forms.sorted().first { forms.isSubset(of: Self.forms(providedBy: $0)) }
			guard let providingForm else { return nil }
			let requiredForms = forms.intersection(requiredReceivedProperties)
			let requiredAliasFulfillingForms = forms.intersection(requiredAliasFulfillingProperties)
			let isProvidingFormRequired = requiredForms.contains(providingForm)
			let property = isProvidingFormRequired || providingForm.typeDescription.isOptional
				? providingForm
				: providingForm.asOptionalProperty
			// An optional wrapper offers no instance, so a parameter made optional provides only the form it was made from.
			guard property == providingForm || forms.isSubset(of: [providingForm, property]) else { return nil }
			return CycleParameter(
				property: property,
				receivedForms: forms,
				requiredForms: requiredForms,
				requiredAliasFulfillingForms: requiredAliasFulfillingForms,
				onlyIfAvailableUnwrappedForms: Set(forms.map(\.asUnwrappedProperty)).intersection(onlyIfAvailableUnwrappedReceivedProperties),
				receiver: receiver,
			)
		}
	}
}

/// The parameters of the builder function a lazy cycle closes on, as the scopes beneath the function see them while
/// their generators are created. Each scope judges what it passes them against the nearest declaration of their labels
/// (see `NearestDeclarations`).
struct CycleParameterContext: Sendable {
	/// The function's parameters.
	let parameters: [CycleParameter]
}
