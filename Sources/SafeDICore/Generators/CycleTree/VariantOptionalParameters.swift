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

extension DependencyTreeGenerator.VariantBodies {
	/// A label a body takes as an optional parameter, whatever each call of it answers the label: one every receive in
	/// the body's tree reads only if available, as today's function takes it (`CycleParameter`). A call whose nearest
	/// declaration hands those receives nothing passes `nil`, and one that hands them a value passes it, so the calls
	/// share one body where a body per answer would double with each such label a path around a cycle can declare.
	struct OptionalParameter: Sendable {
		/// The parameter: the form of the label that provides every form the tree receives, made optional.
		let property: Property
		/// The forms the parameter provides to the body's tree, as a declaration of it does, and the non-optional form it
		/// is made from where the tree receives that form.
		let providedForms: Set<Property>
		/// The forms of the label the body's tree receives, in property order.
		let receivedForms: [Property]
	}

	/// The labels of `labels` a body of `calledScope` built as a property labeled `ownLabel` takes as an optional
	/// parameter, each with its parameter: those every receiver in the scope's tree receives only if available, in forms
	/// one parameter provides, and that no receiver requires through an alias only if available, which orders the
	/// scopes that declare the label. A label received in forms no one parameter provides gets a body per answer, as
	/// does the label the body is built as.
	static func optionalParameters(
		ofTreeOf calledScope: Scope,
		keyedBy labels: [String],
		builtAs ownLabel: String?,
		cache: inout DependencyTreeGenerator.ReceivedPropertiesCache,
	) -> [String: OptionalParameter] {
		let receivedProperties = DependencyTreeGenerator.collectReceivedProperties(from: calledScope, cache: &cache)
		var formsByLabel = [String: Set<Property>]()
		for property in receivedProperties.received {
			formsByLabel[property.label, default: []].insert(property)
		}
		let labelsRequiredThroughAlias = Set(receivedProperties.requiredAliasFulfillingProperties.map(\.label))
		var parameters = [String: OptionalParameter]()
		for label in labels where label != ownLabel && !labelsRequiredThroughAlias.contains(label) {
			guard let forms = formsByLabel[label],
			      forms.isSubset(of: receivedProperties.onlyIfAvailable),
			      let providingForm = forms.sorted().first(where: { forms.isSubset(of: CycleParameter.forms(providedBy: $0)) })
			else { continue }
			let property = providingForm.typeDescription.isOptional ? providingForm : providingForm.asOptionalProperty
			var providedForms = CycleParameter.forms(providedBy: property)
			if forms.contains(property.asUnwrappedProperty) {
				providedForms.insert(property.asUnwrappedProperty)
			}
			parameters[label] = OptionalParameter(property: property, providedForms: providedForms, receivedForms: forms.sorted())
		}
		return parameters
	}

	/// What a call passes `parameter`, the optional parameter of its label, beneath `nearestDeclarations`, or `nil` where
	/// the body the call needs is the one keyed by the call's own answer: `nil` where the label is not answered or every
	/// receive of it reads nothing, and the declaration where every receive reads one property the parameter takes. A
	/// declaration a receive reads as another form, or through a lazily instantiated wrapper, keeps the call's answer,
	/// as does a mock root's binding, which a body reads by what it records of the mock.
	static func argument(
		passing parameter: OptionalParameter,
		labeled label: String,
		isAnswered: Bool,
		beneath nearestDeclarations: NearestDeclarations,
		lazilyInstantiatedInstanceProperties: Set<Property>,
	) -> Answer? {
		guard isAnswered, let declaration = nearestDeclarations[label] else { return Answer.none }
		guard declaration.receivesPassedNil.isEmpty,
		      !declaration.judgesPlacesPinnedFromAbove,
		      !declaration.isBoundByMockRoot,
		      !lazilyInstantiatedInstanceProperties.contains(where: { $0.label == label })
		else { return nil }
		let bindings = Set(parameter.receivedForms.map { nearestDeclarations.resolvingBinding(of: $0).binding })
		guard bindings.count == 1, let binding = bindings.first else { return nil }
		guard let binding else { return Answer.none }
		guard binding == parameter.property || binding == parameter.property.asUnwrappedProperty else { return nil }
		return .declared(binding, isBeingBuilt: false)
	}
}
