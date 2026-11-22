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

/// Stage D1, lane D: the parameters of a mock root's `mock()` other than its overrides, lowered from the mocked type's
/// declaration and its finished generator, as `mockRootParameters(instantiable:mockDefaults:)` computes them for
/// `generateMockRootCode`. Each kind of parameter the lowering does not lower yet returns the rule it belongs to.
extension MockLowering {
	/// The parameters `mock()` takes before its overrides, each under its label, in the order `mock()` declares them.
	struct RootSignature {
		/// A parameter of `mock()`: the property it binds under its label, and its default, if it has one.
		struct Parameter {
			let property: Property
			let defaultExpression: String?
			/// The parameter's type as `mock()` declares it, where that is not the property's type as a parameter.
			var typeSource: String?
		}

		/// The mocked type's `@Forwarded` properties, in property order.
		let forwardedParameters: [Parameter]
		/// The arguments of the mocked type's initializer that take a default and are none of its dependencies, in order.
		let rootDefaultParameters: [Parameter]
		/// The dependencies the tree receives that the mock cannot build, in the mock's order (`precedesInMockOrder`).
		let flatReceivedParameters: [Parameter]
		/// The names the constructions of the root's tree declare `@escaping`, which the parameters spell so.
		let typesDeclaredEscaping: Set<TypeDescription>

		/// The properties the forwarded and received parameters bind, which every node of the tree is built after. The
		/// default-valued ones are the initializer's alone.
		var properties: Set<Property> {
			Set((forwardedParameters + flatReceivedParameters).map(\.property))
		}

		/// The labels the parameters bind, which no node of the tree may bind again.
		var labels: Set<String> {
			Set(parameters.map(\.property.label))
		}

		/// Every parameter, in the order `mock()` declares them.
		var parameters: [Parameter] {
			forwardedParameters + rootDefaultParameters + flatReceivedParameters
		}

		/// The parameters' declarations in `mock()`, at `indent`.
		func parameterLines(indent: String) -> [String] {
			parameters.map { parameter in
				let typeSource = parameter.typeSource ?? parameter.property.typeDescription.asFunctionParameter(amongTypesDeclaredEscaping: typesDeclaredEscaping).asSource
				return if let defaultExpression = parameter.defaultExpression {
					"\(indent)\(parameter.property.label): \(typeSource) = \(defaultExpression)"
				} else {
					"\(indent)\(parameter.property.label): \(typeSource)"
				}
			}
		}
	}
}

extension ScopeGenerator {
	/// The parameters of this mock root's `mock()` other than its overrides, or the first rule they meet that the lowering
	/// does not lower yet.
	func lowerRootSignature(of instantiable: Instantiable, context _: MockContext) -> MockLowering.Lowering<MockLowering.RootSignature> {
		// D1 lane hook (lane D): the forwarded, default-valued and flat received parameters, which lane D's family lowers.
		guard !instantiable.dependencies.contains(where: { $0.source == .forwarded }) else { return .unsupported(.flatParameter) }
		guard Self.defaultValuedMockParameterArguments(of: instantiable).isEmpty else { return .unsupported(.defaultValuedParameter) }
		return .lowered(MockLowering.RootSignature(
			forwardedParameters: [],
			rootDefaultParameters: [],
			flatReceivedParameters: [],
			typesDeclaredEscaping: typesDeclaredEscaping,
		))
	}
}
