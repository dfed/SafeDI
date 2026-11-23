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

/// Stage D1, lane D: the mocked type's own construction, through its hand-written mock where it has one, as
/// `generateMockRootCode` builds it: the call of the mock, its `instantiate()` or its initializer, and the type the mock
/// returns.
extension MockLowering {
	/// The construction `mock()` returns: `instantiable`'s hand-written mock, its `instantiate(…)` or its initializer,
	/// called with `argumentList`.
	static func rootConstruction(of instantiable: Instantiable, argumentList: String) -> String {
		let typeName = instantiable.concreteInstantiable.asSource
		return if instantiable.mockInitializer != nil {
			"\(typeName).\(instantiable.customMockName ?? InstantiableVisitor.mockMethodName)(\(argumentList))"
		} else if instantiable.declarationType.isExtension {
			"\(typeName).\(InstantiableVisitor.instantiateMethodName)(\(argumentList))"
		} else {
			"\(typeName)(\(argumentList))"
		}
	}

	/// The initializer whose arguments `mock()` passes the mocked type's construction: its hand-written mock's, else its
	/// initializer's.
	static func rootConstructionInitializer(of instantiable: Instantiable) -> Initializer? {
		instantiable.mockInitializer ?? instantiable.initializer
	}

	/// The type `mock()` returns: what the hand-written mock returns, else the type itself.
	static func rootReturnType(of instantiable: Instantiable) -> String {
		(instantiable.mockCallReturnType ?? instantiable.concreteInstantiable).asSource
	}
}

/// Stage D1, lane D: what the mocked type's construction is passed of the nodes the root's level binds in another form
/// than the dependency it fulfills (`generateReturnArgumentList`).
extension MockLowering {
	/// The mocked type's own dependencies, received or instantiated, read through the `LazilyInstantiated` wrapper
	/// `instances` holds the instance of: each is passed the wrapper's instance. The root's level names none of their
	/// labels apart.
	static func rootInstancesReadByValue(of instantiable: Instantiable, among instances: Set<Property>) -> Set<Property> {
		var properties = Set<Property>()
		for dependency in instantiable.dependencies where instances.contains(dependency.property.asUnwrappedProperty) {
			switch dependency.source {
			case .received, .instantiated:
				properties.insert(dependency.property)
			case .aliased, .forwarded:
				break
			}
		}
		return properties
	}

	/// The mocked type's own receives only if available of the optional form of a node the root's level binds, or a
	/// parameter of `mock()`, under the receive's label: each is passed that non-optional value.
	static func rootOptionalFormsProvidedByNodes(of instantiable: Instantiable, nodeProperties: Set<Property>, renames _: [String: [TypeDescription: String]]) -> Set<Property> {
		var properties = Set<Property>()
		for dependency in instantiable.dependencies where dependency.source == .received(onlyIfAvailable: true) && dependency.property.typeDescription.isOptional {
			let unwrapped = dependency.property.asUnwrappedProperty
			// D1 lane hook (lane B): a node named apart passes the receive its name (`rootOptionalFormRenames`).
			guard nodeProperties.contains(unwrapped) else { continue }
			properties.insert(dependency.property)
		}
		return properties
	}

	// D1 lane hook (lane B): the mocked type's receive only if available of a node's optional form is passed the name its
	// node is bound apart under, as `generateReturnArgumentList` passes it.
	/// The renames of `rootOptionalFormsProvidedByNodes`' receives whose node the root's level names apart, keyed by the
	/// receive's optional type.
	static func rootOptionalFormRenames(of properties: Set<Property>, renames: [String: [TypeDescription: String]]) -> [String: [TypeDescription: String]] {
		var optionalFormRenames = [String: [TypeDescription: String]]()
		for property in properties where renames[property.label]?[property.typeDescription] == nil {
			guard let name = renames[property.label]?[property.asUnwrappedProperty.typeDescription] else { continue }
			optionalFormRenames[property.label, default: [:]][property.typeDescription] = name
		}
		return optionalFormRenames
	}

	/// The dependency a construction passes `argument`: the one of its label, whatever its type, as the emitter matches
	/// them (`generateReturnArgumentList`, `resolveBuilderArguments`), so a hand-written mock whose parameter is typed
	/// other than the dependency of its label is passed it as generated code passes it.
	static func dependency(passedTo argument: Initializer.Argument, among dependencies: [Dependency]) -> Dependency? {
		dependencies.first { $0.property.label == argument.innerLabel }
	}
}
