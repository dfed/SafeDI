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
	/// The property the parameter binds: the form of the label that provides every other form the function's body
	/// receives, made optional when no receiver requires it, since a scope that calls the function may then have
	/// nothing to pass.
	let property: Property
	/// The forms of the label that the function's body receives from the scopes enclosing it.
	let receivedForms: Set<Property>
	/// Those of `receivedForms` that some receiver requires (see `ScopeGenerator.requiredReceivedProperties`).
	let requiredForms: Set<Property>
	/// Those of `receivedForms` that some receiver requires through an `onlyIfAvailable` alias (see
	/// `ScopeGenerator.requiredAliasFulfillingProperties`).
	let requiredAliasFulfillingForms: Set<Property>
	/// The unwrapped forms of the label that every receiver receives only if available (see
	/// `ScopeGenerator.onlyIfAvailableUnwrappedReceivedProperties`).
	let onlyIfAvailableUnwrappedForms: Set<Property>

	/// Whether every scope that calls the function passes a value: a receiver in its body requires the label.
	var isRequired: Bool {
		!requiredForms.isEmpty || !requiredAliasFulfillingForms.isEmpty
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
	/// enclosing it, for each of `labels` – those a scope between it and one of its cycle-closing scopes declares –
	/// that the tree receives, in label order.
	///
	/// A label is a parameter only when one form the tree receives provides every other: a declaration of that form
	/// does, so each scope that calls the function passes one value. A label received in forms no one declaration
	/// provides – such as `x: X?` and `x: Instantiator<X>?`, each received only if available – is not a parameter, and
	/// the function's body reads it from the scopes enclosing the function, as it does a label no scope between
	/// declares again.
	static func parameters(
		ofLabels labels: Set<String>,
		receivedProperties: Set<Property>,
		requiredReceivedProperties: Set<Property>,
		requiredAliasFulfillingProperties: Set<Property>,
		onlyIfAvailableUnwrappedReceivedProperties: Set<Property>,
	) -> [CycleParameter] {
		var formsByLabel = [String: Set<Property>]()
		for receivedProperty in receivedProperties where labels.contains(receivedProperty.label) {
			formsByLabel[receivedProperty.label, default: []].insert(receivedProperty)
		}
		return formsByLabel.keys.sorted().compactMap { label in
			let forms = formsByLabel[label, default: []]
			// A label received in forms no one declaration provides is left out: a deliberate gap (see above).
			let providingForm = forms.sorted().first { forms.isSubset(of: Self.forms(providedBy: $0)) }
			guard let providingForm else { return nil }
			let requiredForms = forms.intersection(requiredReceivedProperties)
			let requiredAliasFulfillingForms = forms.intersection(requiredAliasFulfillingProperties)
			let isProvidingFormRequired = requiredForms.contains(providingForm) || requiredAliasFulfillingForms.contains(providingForm)
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
			)
		}
	}
}

/// The parameters of the builder function a lazy cycle closes on, as the scopes beneath the function see them while
/// their generators are created: for each parameter's label, what the nearest scope between the function and them
/// declares under it.
struct CycleParameterContext: Sendable {
	init(parameters: [CycleParameter]) {
		self.parameters = parameters
		nearestDeclaredFormsByLabel = [:]
	}

	/// The function's parameters.
	let parameters: [CycleParameter]
	/// For each parameter's label that a scope between the function and the scope this context is given to declares,
	/// the forms the nearest such scope declares under it, with the instance of a lazily instantiated one. A label
	/// absent here resolves to the function's parameter.
	private(set) var nearestDeclaredFormsByLabel: [String: Set<Property>]

	/// The forms the nearest declaration of `label` beneath the function provides, or `nil` when the function's
	/// parameter is the nearest declaration.
	func nearestDeclaredForms(ofLabel label: String) -> Set<Property>? {
		nearestDeclaredFormsByLabel[label]
	}

	/// This context as the scopes beneath a scope that declares `declaredProperties` see it.
	func declaring(_ declaredProperties: Set<Property>) -> CycleParameterContext {
		var context = self
		for parameter in parameters {
			let declaredForms = declaredProperties.filter { $0.label == parameter.property.label }
			if !declaredForms.isEmpty {
				context.nearestDeclaredFormsByLabel[parameter.property.label] = declaredForms
			}
		}
		return context
	}
}
