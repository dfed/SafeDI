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

/// The parameter a variant's builder function takes for one read from above.
///
/// Stands in for the cycles integrator's cycle parameter type fact (`lanes/cycles-once-per-type/parameter-type-interface.md`),
/// with its signatures, until that fact lands and replaces this file's declarations.
struct TypeFactsParameter: Hashable, Sendable {
	/// The parameter as the function declares it: the read's label, and its type.
	let property: Property
	/// Whether the body reads the value through the wrapper's `instance`.
	let readsInstanceOfWrapper: Bool
}

/// The parameters a test hands the stand-in for the cycle parameter type fact, by the name of the type a variant's
/// declaration builds. Only a test sets it, until the fact lands.
public enum CycleParametersForTesting {
	@TaskLocal public static var byTypeName = [String: [Property]]()
}

extension TypeFactsWorld {
	/// Every parameter `variant`'s function takes, in the order of `parameterOrder(of:)` for its declaration: exactly
	/// today's `CycleParameterPlan` parameters of the function a cycle closes on. The stand-in answers what a test hands it
	/// (`CycleParametersForTesting`), and no parameter for any other variant.
	func parameters(of variant: VariantID) -> [TypeFactsParameter] {
		guard let records = self as? any NodeRecordSources else { return [] }
		let typeName = records.scope(of: declaration(of: variant)).instantiable.concreteInstantiable.asSource
		return CycleParametersForTesting.byTypeName[typeName, default: []].map { TypeFactsParameter(property: $0, readsInstanceOfWrapper: false) }
	}
}

extension NodeRecords {
	/// What every call of `variant`'s function passes its parameters, a call that closes a cycle on it included: by
	/// parameter, `nil` where the label is unavailable to the variant, a lazily instantiated wrapper's instance where the
	/// parameter takes the value by its wrapper, else the label's binding. Every call of a variant shares its keys, so each
	/// passes the same.
	static func cycleArguments(
		of parameters: [TypeFactsParameter],
		unavailableProperties: Set<Property>,
		lazilyInstantiatedInstanceProperties: Set<Property>,
	) -> [PlaceRead] {
		parameters.map { parameter in
			let property = parameter.property
			let source: ArgumentSource = if unavailableProperties.contains(property) {
				.nil
			} else if let instanceSource = lazilyInstantiatedInstanceProperties.lazilyInstantiatedInstanceSource(of: property, boundAs: property.label) {
				instanceSource
			} else {
				.binding(label: property.label)
			}
			return PlaceRead(argumentLabel: property.label, label: property.label, property: property, source: source)
		}
	}
}
