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
/// The place records of a mock's closers and defaults: what the mock walk hands production's record functions
/// (`ScopeGenerator.closingPlaceRecord(of:…)`) at a place that closes a cycle, or whose builder function a default, a
/// `@Sendable` autoclosure or a receiver's rebinding decides, so the type key can lay a mock out as it lays out production.
extension MockLowering.Walk {
	/// The record of the closer of `generator`, bound as `bindingName`, which calls the function named
	/// `closedOnFunctionName`, or `nil` where the type key does not plan it: a member of a loop of builders, or a place the
	/// generator writes with anything the type key does not plan (`ScopeGenerator.isPlannedByGenerator`).
	func closerRecord(
		of generator: ScopeGenerator,
		instantiable: Instantiable,
		property: Property,
		erasedToConcreteExistential: Bool,
		forwardedProperties: [Property],
		closedOnFunctionName: String,
	) -> PlaceRecord? {
		generator.closingPlaceRecord(
			of: property,
			instantiable: instantiable,
			forwardedProperties: forwardedProperties,
			erasedToConcreteExistential: erasedToConcreteExistential,
			closedOnFunctionName: closedOnFunctionName,
			unavailableProperties: unavailableProperties,
			isPlannedAtPlace: loopMembership == nil,
			readNames: cycleParameterReadNames(of: generator),
		)
	}

	/// The names the mock binds the labels of `generator`'s cycle parameters apart under, where it binds one apart, by the
	/// parameter's property: what `MockLowering.cycleParameterArguments(of:…)` passes in place of the label.
	func cycleParameterReadNames(of generator: ScopeGenerator) -> [Property: String] {
		let lazilyInstantiatedInstanceProperties = generator.mockLoweringCallSiteLazilyInstantiatedInstanceProperties
		var readNames = [Property: String]()
		for parameter in generator.cycleParameters where !unavailableProperties.contains(parameter.property) {
			let label = parameter.property.label
			let name: String? = if lazilyInstantiatedInstanceProperties.contains(parameter.property.asUnwrappedProperty) {
				// The instance is read from the wrapper of its label the mock names apart, where it names one apart.
				[Dependency.lazilyInstantiatedType, Dependency.sendableLazilyInstantiatedType].lazy.compactMap { renames[label]?[.simple(name: $0, generics: [parameter.property.asUnwrappedProperty.typeDescription])] }.first
			} else {
				lazilyInstantiatedNames[label]?[parameter.property.typeDescription] ?? renames[label]?[parameter.property.typeDescription] ?? renames[label]?[parameter.property.asUnwrappedProperty.typeDescription]
			}
			if let name, name != label {
				readNames[parameter.property] = name
			}
		}
		return readNames
	}
}

extension MockLowering {
	/// Whether a node the mock builds writes a builder function: where it builds children or a wrapper, as production's
	/// place does, and also where its function binds a receive named apart again (`receiverBindings`), reads a default from
	/// its configuration (`readsDefaults`), or binds the value of a `@Sendable` autoclosure parameter of `mock()`
	/// (`hasSendableAutoclosureBindings`), which production's place never does: the input the mock walk hands production's
	/// built record function for whether the place has a function.
	static func writesBuilderFunction(hasChildren: Bool, isWrapped: Bool, hasReceiverBindings: Bool, readsDefaults: Bool, hasSendableAutoclosureBindings: Bool) -> Bool {
		hasChildren || isWrapped || hasReceiverBindings || readsDefaults || hasSendableAutoclosureBindings
	}

	/// The statements that begin a node's builder function, before its children's, as places the type key reads: each
	/// receive named apart bound again under its label, then the value of each `@Sendable` autoclosure parameter the node
	/// instantiates, as `ConstantNode.receiverBindingLines(indent:)` writes them, unindented. Each is a place written as
	/// text whose one read is the name it binds from: the name the receive is bound apart under, or the local `mock()`
	/// reads the autoclosure into (`RootDeclarationRecord`).
	static func receiverBindingPlaces(
		receiverBindings: [(property: Property, name: String)],
		sendableAutoclosureBindings: [(property: Property, parameter: ScopeGenerator.SendableAutoclosureParameter)],
	) -> [GeneratedCode] {
		var places = [GeneratedCode]()
		for binding in receiverBindings {
			let read = Property(label: binding.name, typeDescription: binding.property.typeDescription)
			places.append(.place(PlacePlan(
				code: .text("let \(binding.property.label): \(binding.property.typeDescription.asSource) = \(binding.name)"),
				record: .alias(AliasPlaceRecord(
					property: binding.property,
					fulfillingProperty: read,
					text: "let \(binding.property.label): \(binding.property.typeDescription.asSource) = \(binding.name)",
					reads: [PlaceRead(argumentLabel: binding.property.label, label: binding.name, property: read, source: .binding(label: binding.name))],
				)),
			)))
		}
		for (property, parameter) in sendableAutoclosureBindings {
			let read = sendableAutoclosureLocalProperty(of: parameter, builds: property)
			places.append(.place(PlacePlan(
				code: .text(parameter.binding),
				record: .alias(AliasPlaceRecord(
					property: Property(label: parameter.name, typeDescription: property.typeDescription),
					fulfillingProperty: nil,
					text: parameter.binding,
					reads: [PlaceRead(argumentLabel: parameter.name, label: parameter.localName, property: read, source: .binding(label: parameter.localName))],
				)),
			)))
		}
		return places
	}

	/// The declaration `mock()` binds a `@Sendable` autoclosure parameter's closure under at the root's top, which builds
	/// `property`: what a binding of its value reads, and what the root records it as (`RootDeclarationRecord`).
	static func sendableAutoclosureLocalProperty(of parameter: ScopeGenerator.SendableAutoclosureParameter, builds property: Property) -> Property {
		let valueType = parameter.valueType ?? property.typeDescription
		return Property(
			label: parameter.localName,
			typeDescription: .attributed(.closure(arguments: [], isAsync: false, doesThrow: false, returnType: valueType), specifiers: [], attributes: ["Sendable"]),
		)
	}
}
