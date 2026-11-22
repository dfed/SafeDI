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

		// D1 lane hook (lane D): the `@Instantiated` dependencies of the tree's types that the mock cannot build, which
		// `mock()` takes after the received ones, and the documentation of those several types create.
		/// The properties of the `@Instantiated` dependencies the mock cannot build, which a type of the tree is passed.
		var uncoveredProperties: Set<Property> {
			[]
		}

		/// The lines that document, above `mock()`, each parameter several types create, at `indent`.
		func sharedValueDocumentationLines(indent _: String) -> [String] {
			[]
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
	func lowerRootSignature(of instantiable: Instantiable, context: MockContext) -> MockLowering.Lowering<MockLowering.RootSignature> {
		var forwardedParameters = [MockLowering.RootSignature.Parameter]()
		for dependency in instantiable.dependencies.sorted(by: { $0.property < $1.property }) where dependency.source == .forwarded {
			// A forwarded wrapper declares the forms of its instance beside it, which the tree's receives read.
			guard dependency.property.propertyType.isConstant else { return .unsupported(.wrapper) }
			// The default the initializer gives the parameter of its label wins over the hand-written mock its type has.
			let constructionDefault = instantiable.initializer?.arguments.first { $0.innerLabel == dependency.property.label }?.defaultValueExpression
			forwardedParameters.append(MockLowering.RootSignature.Parameter(
				property: dependency.property,
				defaultExpression: constructionDefault ?? context.flatParameterMockDefaults[dependency.property.typeDescription]?.expression,
			))
		}
		var rootDefaultParameters = [MockLowering.RootSignature.Parameter]()
		for (argument, defaultExpression) in Self.defaultValuedMockParameterArguments(of: instantiable) {
			// `mock()` takes an `@autoclosure` as one and passes its call, so the value is evaluated where the type is built.
			guard argument.typeDescription.strippingEscaping.autoclosureValueType == nil else { return .unsupported(.defaultValuedParameter) }
			rootDefaultParameters.append(MockLowering.RootSignature.Parameter(
				property: Property(label: argument.label, typeDescription: argument.typeDescription),
				defaultExpression: defaultExpression,
				typeSource: argument.typeDescription.asFunctionParameter.asSource,
			))
		}
		// The forms of what the tree receives only if available are overrides of `mock()`, not parameters.
		guard onlyIfAvailableUnwrappedReceivedProperties.isEmpty else { return .unsupported(.onlyIfAvailable) }
		// Each in the mocked type's own spelling where it receives the dependency, else its receivers' most explicit one.
		let receivedProperties = MockedTypeSpellings(of: instantiable, treeReceivedProperties: receivedProperties).spellings(of: receivedProperties)
		// The mock wraps the instance it is passed for a `LazilyInstantiated` it cannot build.
		guard !receivedProperties.contains(where: { $0.typeDescription.lazilyInstantiatedInstanceType != nil }) else { return .unsupported(.wrapper) }
		let forwardedProperties = instantiable.forwardedReceivableProperties
		let receivedNonOptionalProperties = Set(receivedProperties.filter { !$0.typeDescription.isOptional })
		var flatReceivedParameters = [MockLowering.RootSignature.Parameter]()
		for property in receivedProperties.sorted(by: { $0.precedesInMockOrder($1) }) {
			// A forwarded `x: X` fulfills an `x: X?` too, and so does a received `x: X`, which the parameter of its own binds.
			guard !forwardedProperties.contains(property),
			      !property.typeDescription.isOptional
			      || !receivedNonOptionalProperties.contains(property.asUnwrappedProperty) && !forwardedProperties.contains(property.asUnwrappedProperty)
			else { continue }
			// A node the mock promotes for an optional receive binds its non-optional value, which provides this one.
			guard property.typeDescription.isOptional || !propertiesToDeclare.contains(property.asOptionalProperty) else { return .unsupported(.flatParameter) }
			guard !Self.provides(property, declaredProperties: propertiesToDeclare, forwardedProperties: []) else { continue }
			flatReceivedParameters.append(MockLowering.RootSignature.Parameter(
				property: property,
				defaultExpression: context.flatParameterMockDefaults[property.typeDescription]?.expression,
			))
		}
		// Two parameters of one label are named apart.
		let parameters = forwardedParameters + rootDefaultParameters + flatReceivedParameters
		guard Set(parameters.map(\.property.label)).count == parameters.count else { return .unsupported(.siblingLabelCollision) }
		return .lowered(MockLowering.RootSignature(
			forwardedParameters: forwardedParameters,
			rootDefaultParameters: rootDefaultParameters,
			flatReceivedParameters: flatReceivedParameters,
			typesDeclaredEscaping: typesDeclaredEscaping,
		))
	}
}
