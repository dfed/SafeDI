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

/// Stage D1's lane B: the parameters of a builder function a lazy cycle closes on (`CycleParameter` in
/// `cycle-generation.md`), which the function declares after its forwarded properties and every call of it passes.
extension MockLowering {
	/// The arguments a call of the builder function that `generator`'s node declares or closes on passes its cycle
	/// parameters, where the node is built: `nil` for one the node is built where nothing provides, a lazy wrapper's
	/// instance, or the binding of the label. `unavailableProperties` are what the node is passed `nil` for where its level builds it
	/// (`ScopeGenerator.OrderedChild.unavailableProperties`), a parameter it passes `nil` among them, as the emitter's
	/// `cycleParameterArgumentUnavailableProperties` reads them. `renames` are the names the mock binds a label apart
	/// under, and `lazilyInstantiatedNames` the wrappers it binds around the instances it is passed, as
	/// `mockCycleParameterArguments` reads them. `insideSendableFunction` says whether the call is made inside a `@Sendable`
	/// function: the node's own `Sendable` wrapper's closure, or one around it.
	static func cycleParameterArguments(of generator: ScopeGenerator, inScope _: Set<Property>, unavailableProperties: Set<Property>, renames: [String: [TypeDescription: String]], lazilyInstantiatedNames: [String: [TypeDescription: String]], insideSendableFunction: Bool) -> [String] {
		let lazilyInstantiatedInstanceProperties = generator.mockLoweringCallSiteLazilyInstantiatedInstanceProperties
		var arguments = [String]()
		for parameter in generator.cycleParameters {
			let label = parameter.property.label
			let value: String
			if unavailableProperties.contains(parameter.property) {
				value = "nil"
			} else if lazilyInstantiatedInstanceProperties.contains(parameter.property.asUnwrappedProperty) {
				// A deliberate gap, as the emitter's: see "Eager instances at a lazy cycle's calls" in `cycle-generation.md`. The
				// instance is read from the wrapper of its label the mock names apart, where it names one apart.
				let instanceType = parameter.property.asUnwrappedProperty.typeDescription
				let wrapperName = lazyWrapperTypeNames(insideSendableFunction: insideSendableFunction).lazy.compactMap { renames[label]?[.simple(name: $0, generics: [instanceType])] }.first
				value = "\(wrapperName ?? label).\(Dependency.lazilyInstantiatedInstancePropertyName)"
			} else {
				// The binding the label is named apart under (`mockCycleParameterArguments`).
				value = lazilyInstantiatedNames[label]?[parameter.property.typeDescription] ?? renames[label]?[parameter.property.typeDescription] ?? renames[label]?[parameter.property.asUnwrappedProperty.typeDescription] ?? label
			}
			arguments.append("\(label.spelledAsArgumentLabel): \(value)")
		}
		return arguments
	}

	/// The forms of `generator`'s cycle parameters, which its builder function's body reads as the nearest declarations
	/// of their labels.
	static func cycleParameterForms(of generator: ScopeGenerator) -> Set<Property> {
		Set(generator.cycleParameters.flatMap(\.providedForms))
	}
}
