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

import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

public struct InjectableMacro: PeerMacro {
	public static func expansion(
		of node: AttributeSyntax,
		providingPeersOf declaration: some DeclSyntaxProtocol,
		in context: some MacroExpansionContext,
	)
		throws -> [DeclSyntax]
	{
		let attributeName = node.attributeName.trimmedDescription
		guard let variableDecl = VariableDeclSyntax(declaration) else {
			throw InjectableError.notDecoratingBinding(attributeName: attributeName)
		}

		guard variableDecl.modifiers.staticModifier == nil else {
			throw InjectableError.decoratingStatic(attributeName: attributeName)
		}

		let macroWithParameters = variableDecl.attributes.instantiatedMacro ?? variableDecl.attributes.receivedMacro
		if let fulfilledByType = macroWithParameters?.fulfilledByType {
			let decoratesInstantiator = variableDecl
				.bindings
				.compactMap(\.typeAnnotation)
				.contains(where: \.type.typeDescription.propertyType.isInstantiator)
			if decoratesInstantiator {
				throw InjectableError.fulfilledByTypeUseOnInstantiator
			}

			if let stringLiteralExpression = StringLiteralExprSyntax(fulfilledByType),
			   stringLiteralExpression.segments.count == 1,
			   case let .stringSegment(stringLiteral) = stringLiteralExpression.segments.first
			{
				switch TypeSyntax(stringLiteral: stringLiteral.content.text).typeDescription {
				case .simple, .nested:
					break
				case .composition, .optional, .implicitlyUnwrappedOptional, .some, .any, .metatype, .attributed, .array, .dictionary, .tuple, .closure, .unknown, .void:
					throw InjectableError.fulfilledByTypeArgumentInvalidTypeDescription
				}
			} else {
				throw InjectableError.fulfilledByTypeArgumentInvalidType
			}
		} else {
			let decoratesErasedInstantiator = variableDecl
				.bindings
				.compactMap(\.typeAnnotation)
				.contains(where: \.type.typeDescription.propertyType.isErasedInstantiator)
			if decoratesErasedInstantiator {
				throw InjectableError.erasedInstantiatorUsedWithoutFulfilledByType
			}
		}

		if let fulfilledByDependencyNamed = macroWithParameters?.fulfilledByDependencyNamed {
			guard let stringLiteralExpression = StringLiteralExprSyntax(fulfilledByDependencyNamed),
			      stringLiteralExpression.segments.count == 1
			else {
				throw InjectableError.fulfilledByDependencyNamedInvalidType
			}
		}

		if let fulfilledByType = macroWithParameters?.ofType, case .unknown = fulfilledByType.typeDescription {
			throw InjectableError.ofTypeArgumentInvalidType
		}

		if let erasedToConcreteExistential = macroWithParameters?.erasedToConcreteExistential, BooleanLiteralExprSyntax(erasedToConcreteExistential) == nil {
			throw InjectableError.erasedToConcreteExistentialInvalidType
		}

		if let onlyIfAvailable = macroWithParameters?.onlyIfAvailable {
			if BooleanLiteralExprSyntax(onlyIfAvailable) == nil {
				throw InjectableError.onlyIfAvailableInvalidType
			}
			if !variableDecl.bindings.compactMap(\.typeAnnotation).allSatisfy(\.type.typeDescription.isOptional) {
				context.diagnose(Diagnostic(
					node: variableDecl.bindings,
					error: FixableInjectableError.onlyIfAvailableNotOptionalSpelledWithQuestionMark,
					changes: [
						.replace(
							oldNode: Syntax(variableDecl.bindings),
							newNode: Syntax(PatternBindingListSyntax(itemsBuilder: {
								variableDecl.bindings.compactMap {
									$0.with(\.typeAnnotation, $0.typeAnnotation.map {
										$0.with(\.type, {
											TypeSyntax(OptionalTypeSyntax(
												wrappedType: $0.type,
												questionMark: .postfixQuestionMarkToken(),
											))
										}($0))
									})
								}
							})),
						),
					],
				))
			}
		}

		if variableDecl.bindingSpecifier.text != TokenSyntax.keyword(.let).text,
		   // If there is only one attribute, we know the variable is not decorated with a property wrapper.
		   variableDecl.attributes.count == 1
		{
			context.diagnose(Diagnostic(
				node: variableDecl.bindingSpecifier,
				error: FixableInjectableError.unexpectedMutable,
				changes: [
					.replace(
						oldNode: Syntax(variableDecl.bindingSpecifier),
						newNode: Syntax(TokenSyntax.keyword(
							.let,
							leadingTrivia: .space,
							trailingTrivia: .space,
						)),
					),
				],
			))
		}

		// This macro purposefully does not expand.
		// This macro serves as a decorator, nothing more.
		return []
	}

	// MARK: - InjectableError

	private enum InjectableError: Error, CustomStringConvertible {
		case notDecoratingBinding(attributeName: String)
		case decoratingStatic(attributeName: String)
		case fulfilledByTypeArgumentInvalidType
		case fulfilledByTypeArgumentInvalidTypeDescription
		case fulfilledByDependencyNamedInvalidType
		case fulfilledByTypeUseOnInstantiator
		case ofTypeArgumentInvalidType
		case erasedToConcreteExistentialInvalidType
		case erasedInstantiatorUsedWithoutFulfilledByType
		case onlyIfAvailableInvalidType

		var description: String {
			switch self {
			case let .notDecoratingBinding(attributeName):
				"@\(attributeName) must decorate an instance property."
			case let .decoratingStatic(attributeName):
				"@\(attributeName) cannot decorate a `static` property. Make it an instance property."
			case .fulfilledByTypeArgumentInvalidType:
				"The argument `fulfilledByType` must be a string literal."
			case .fulfilledByTypeArgumentInvalidTypeDescription:
				"The argument `fulfilledByType` must name a type, such as \"DefaultService\" or \"Module.DefaultService\", not an optional, existential, composition, metatype, collection, tuple, or closure type."
			case .fulfilledByDependencyNamedInvalidType:
				"The argument `fulfilledByDependencyNamed` must be a string literal."
			case .fulfilledByTypeUseOnInstantiator:
				"The argument `fulfilledByType` cannot be used on an `Instantiator` or `SendableInstantiator`. Use an `ErasedInstantiator` or `SendableErasedInstantiator` instead."
			case .ofTypeArgumentInvalidType:
				"The argument `ofType` must be a type literal, such as `Service.self`."
			case .erasedToConcreteExistentialInvalidType:
				"The argument `erasedToConcreteExistential` must be a Bool literal (`true` or `false`)."
			case .erasedInstantiatorUsedWithoutFulfilledByType:
				"An `ErasedInstantiator` or `SendableErasedInstantiator` property must name the type it builds with the argument `fulfilledByType`, such as `@Instantiated(fulfilledByType: \"DefaultService\")`. Use an `Instantiator` or `SendableInstantiator` when the property’s type is the type it builds."
			case .onlyIfAvailableInvalidType:
				"The argument `onlyIfAvailable` must be a Bool literal (`true` or `false`)."
			}
		}
	}
}
