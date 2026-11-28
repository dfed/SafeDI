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

// The mock kind `mockDefaultValuedParameter`: a node whose construction takes a parameter with a default value, which a
// mock holds as a field of the type's configuration and the node's construction reads.
extension NodeRecords {
	/// Whether a call of `construction` a mock writes passes a value no record makes yet. An argument a dependency of
	/// `dependencies` fulfills is that dependency's read, a default-valued one no dependency's label names is a field of the
	/// node's configuration (`mockConfigurationFieldArguments(of:in:)`) or left to its default
	/// (`Initializer.Argument.isLeftToItsDefault`), and every other one is refused: an argument a dependency's label names
	/// without fulfilling it, which the mock's walk passes that dependency, and a `@Sendable` `@autoclosure`, which it
	/// passes a local the node's function reads the configuration into.
	static func passesValueNoRecordMakes(_ construction: Initializer, given dependencies: [Dependency]) -> Bool {
		construction.arguments.contains { argument in
			guard !dependencies.contains(where: argument.isFulfilled(by:)) else { return false }
			guard !dependencies.contains(where: { $0.property.label == argument.innerLabel }), argument.hasDefaultValue else { return true }
			return !argument.isLeftToItsDefault && MockLowering.isSendableAutoclosure(argument.typeDescription)
		}
	}

	/// The arguments of the function that builds `declaration`'s node in a mock whose values are fields of the node's
	/// configuration: each default-valued one no dependency fulfills that the call does not leave to its default, with its
	/// position among the arguments the call passes, in the function's order. A node with such a field is configured,
	/// though it builds no child, and is always built in a function of its own, as the mock's walk builds it.
	static func mockConfigurationFieldArguments(of declaration: DeclarationID, in world: some NodeRecordSources) -> [(position: Int, argument: Initializer.Argument)] {
		let dependencies = world.scope(of: declaration).instantiable.dependencies
		var fieldArguments = [(position: Int, argument: Initializer.Argument)]()
		var position = 0
		for argument in mockConstructionFunction(of: declaration, in: world)?.arguments ?? [] {
			if dependencies.contains(where: argument.isFulfilled(by:)) {
				position += 1
			} else if argument.hasDefaultValue, !argument.isLeftToItsDefault {
				fieldArguments.append((position: position, argument: argument))
				position += 1
			}
		}
		return fieldArguments
	}

	/// What a construction is passed for `argument`, a field of the configuration `configuration` reads
	/// (`mockConfigurationFieldArguments(of:in:)`): the field, or, where the field is a closure, a call of it, once where
	/// the node is built. The field is a closure for an `@autoclosure` parameter, and for every value that is no function
	/// where the configuration takes the `Sendable` form (`storesFieldsAsClosures`), as the mock's walk reads it.
	static func mockConfigurationFieldValue(of argument: Initializer.Argument, readFrom configuration: ValuePath, storesFieldsAsClosures: Bool) -> ValuePath {
		let typeDescription = argument.typeDescription.strippingEscaping
		if typeDescription.autoclosureValueType == nil, !storesFieldsAsClosures || typeDescription.isClosure {
			return .member(argument.label, of: configuration)
		} else {
			return .call(argument.label, of: configuration, arguments: [], argumentsWrapper: nil)
		}
	}
}
