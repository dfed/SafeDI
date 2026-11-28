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

extension NodeRecords {
	/// What one call of `variant`'s function passes its parameters, a call that closes a cycle on it included, where the
	/// call holds the by-value properties of `lazilyInstantiatedInstanceProperties` only as a wrapper's instance: by
	/// parameter, `nil` where the label is unavailable to the variant; for a parameter that is a lazily instantiated
	/// wrapper, the call's wrapper where it holds one, else a wrapper made of the value it holds; for a parameter by value,
	/// the instance of the call's wrapper where it holds one; else the label's binding. Calls of one variant share its keys
	/// but not what declares each label at them, so each call passes its own.
	static func cycleArguments(
		of parameters: [TypeFactsParameter],
		unavailableProperties: Set<Property>,
		lazilyInstantiatedInstanceProperties: Set<Property>,
	) -> [PlaceRead] {
		parameters.map { parameter in
			let property = parameter.property
			let wrapper = property.asUnwrappedProperty
			let source: ArgumentSource = if unavailableProperties.contains(property) {
				.nil
			} else if wrapper.propertyType.isLazilyInstantiated, let instance = wrapper.asLazilyInstantiatedInstanceProperty {
				if lazilyInstantiatedInstanceProperties.contains(instance) || lazilyInstantiatedInstanceProperties.contains(instance.asOptionalProperty) {
					.binding(label: property.label)
				} else {
					.wrapper(of: .binding(label: property.label), wrapperType: wrapper.typeDescription)
				}
			} else if let instanceSource = lazilyInstantiatedInstanceProperties.lazilyInstantiatedInstanceSource(of: property, boundAs: property.label) {
				instanceSource
			} else {
				.binding(label: property.label)
			}
			return PlaceRead(argumentLabel: property.label, label: property.label, property: property, source: source)
		}
	}
}
