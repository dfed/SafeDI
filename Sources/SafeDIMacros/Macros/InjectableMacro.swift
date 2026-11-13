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
				case .composition, .optional, .implicitlyUnwrappedOptional, .some, .any, .metatype, .attributed, .array, .dictionary, .tuple, .closure, .unknown, .variadic, .void:
					throw InjectableError.fulfilledByTypeArgumentInvalidTypeDescription
				}
			} else {
				throw InjectableError.fulfilledByTypeArgumentInvalidType
			}
		} else if variableDecl.attributes.instantiatedMacro != nil {
			// An @Received or @Forwarded erased instantiator is handed in rather than built, so it names no type to build.
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

		if let macroWithParameters, macroWithParameters.erasedToConcreteExistentialValue {
			let isRename = macroWithParameters.fulfilledByDependencyNamed != nil
			// Every initializer of a SafeDI wrapper takes a function that builds the value, so a rename erases into a
			// wrapper only a dependency spelled as a function.
			let renamesFunction = macroWithParameters.ofType.map { Self.isFunctionType($0.typeDescription) } ?? false
			if isRename, !renamesFunction {
				for binding in variableDecl.bindings {
					if let wrapperTypeName = binding.typeAnnotation?.type.typeDescription.propertyType.wrapperTypeName {
						throw InjectableError.erasedRenameIntoWrapper(wrapperTypeName: wrapperTypeName)
					}
				}
			}

			// A bare type name may be a concrete existential or a protocol, which only the compiler can tell apart, so
			// only an existential spelled with `any` or as a composition (`P & Q`), which never has an initializer, is
			// diagnosed.
			let typesErasedToExistentialWithoutInitializer = variableDecl.bindings.compactMap { binding -> TypeSyntax? in
				guard let type = binding.typeAnnotation?.type,
				      Self.isExistentialWithoutInitializer(Self.erasedType(ofPropertyTyped: type.typeDescription, isRename: isRename))
				else {
					return nil
				}
				return type
			}
			if let type = typesErasedToExistentialWithoutInitializer.first,
			   let arguments = macroWithParameters.arguments.flatMap({ LabeledExprListSyntax($0) })
			{
				context.diagnose(Diagnostic(
					node: type,
					error: FixableInjectableError.erasedToConcreteExistentialOnExistentialWithoutInitializer,
					changes: [
						.replace(
							oldNode: Syntax(arguments),
							newNode: Syntax(Self.removingErasedToConcreteExistential(from: arguments)),
						),
					],
				))
			}
		}

		if let onlyIfAvailable = macroWithParameters?.onlyIfAvailable {
			if BooleanLiteralExprSyntax(onlyIfAvailable) == nil {
				throw InjectableError.onlyIfAvailableInvalidType
			}
			if !variableDecl.bindings.compactMap(\.typeAnnotation).allSatisfy(\.type.typeDescription.isOptional) {
				context.diagnose(Self.optionalTypeRequired(
					in: variableDecl,
					error: .onlyIfAvailableNotOptionalSpelledWithQuestionMark,
				))
			}
		} else if let macroWithParameters,
		          macroWithParameters.fulfilledByDependencyNamed != nil,
		          macroWithParameters.erasedToConcreteExistentialValue,
		          macroWithParameters.ofType?.typeDescription.isOptional == true,
		          !variableDecl.bindings.compactMap(\.typeAnnotation).allSatisfy(\.type.typeDescription.isOptional)
		{
			// An erased rename of an optional dependency wraps the dependency where it is present and is `nil` where it is
			// not. A rename that also sets `onlyIfAvailable` gets the check above instead, so nothing is reported twice.
			context.diagnose(Self.optionalTypeRequired(
				in: variableDecl,
				error: .erasedRenameOfOptionalDependencyNotOptionalSpelledWithQuestionMark,
			))
		}

		if variableDecl.attributes.instantiatedMacro != nil {
			for binding in variableDecl.bindings {
				if let type = binding.typeAnnotation?.type,
				   let nonOptionalType = Self.nonOptional(instantiatedPropertyType: type)
				{
					context.diagnose(Diagnostic(
						node: type,
						error: FixableInjectableError.instantiatedPropertyTypeIsOptional(
							nonOptionalDeclaration: "\(binding.pattern.trimmedDescription): \(nonOptionalType.trimmedDescription)",
						),
						changes: [
							.replace(
								oldNode: Syntax(type),
								newNode: Syntax(nonOptionalType),
							),
						],
					))
				}
			}
		}

		// Forwarding a SafeDI wrapper is deprecated in 2.3.0 and an error in 3.0. Asked of the attribute this expansion is
		// for, so a property that also carries another SafeDI attribute, which the `@Instantiable` macro rejects, is
		// warned about once.
		if AttributeListSyntax.Element.attribute(node).forwardedMacro != nil {
			for binding in variableDecl.bindings {
				if let type = binding.typeAnnotation?.type,
				   let wrapperTypeName = type.typeDescription.propertyType.wrapperTypeName
				{
					context.diagnose(Diagnostic(
						node: type,
						message: InjectableDeprecation.forwardedWrapper(wrapperTypeName: wrapperTypeName),
					))
				}
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

	/// `error` at `variableDecl`'s bindings, with a fix-it that spells each binding's type optional with `?`.
	private static func optionalTypeRequired(
		in variableDecl: VariableDeclSyntax,
		error: FixableInjectableError,
	) -> Diagnostic {
		Diagnostic(
			node: variableDecl.bindings,
			error: error,
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
		)
	}

	/// `type`, the type of an `@Instantiated` property, without the optionality SafeDI cannot give it, or `nil` when it
	/// has none. SafeDI always creates the property, so neither its type nor the type a SafeDI wrapper builds, such as
	/// the `X` of `Instantiator<X>`, may be optional.
	private static func nonOptional(instantiatedPropertyType type: TypeSyntax) -> TypeSyntax? {
		let unwrappedType = withoutOptionality(type)
		let nonOptionalType = unwrappedType ?? type
		guard let identifierType = IdentifierTypeSyntax(nonOptionalType),
		      let genericArgumentClause = identifierType.genericArgumentClause
		else {
			return unwrappedType
		}
		var arguments = Array(genericArgumentClause.arguments)
		guard let builtTypeIndex = builtTypeIndex(of: nonOptionalType.typeDescription.propertyType),
		      builtTypeIndex < arguments.count,
		      let builtType = TypeSyntax(arguments[builtTypeIndex].argument),
		      let nonOptionalBuiltType = withoutOptionality(builtType)
		else {
			return unwrappedType
		}
		arguments[builtTypeIndex] = arguments[builtTypeIndex].with(\.argument, .type(nonOptionalBuiltType))
		return TypeSyntax(identifierType.with(
			\.genericArgumentClause,
			genericArgumentClause.with(\.arguments, GenericArgumentListSyntax(arguments)),
		))
	}

	/// The index of the generic argument that a SafeDI wrapper of `propertyType` builds, or `nil` for a constant.
	private static func builtTypeIndex(of propertyType: Property.PropertyType) -> Int? {
		switch propertyType {
		case .constant:
			nil
		case .instantiator, .sendableInstantiator, .lazilyInstantiated, .sendableLazilyInstantiated:
			0
		case .erasedInstantiator, .sendableErasedInstantiator:
			1
		}
	}

	/// The type to whose no-label initializer generated code passes the value of a property of `propertyType` declared
	/// with `erasedToConcreteExistential: true`. A rename's value is passed to its property's type, without the
	/// optionality an `onlyIfAvailable` rename or a rename of an optional dependency has; an `@Instantiated` property's
	/// instance is passed to the type its SafeDI wrapper builds, or to the property's type.
	private static func erasedType(ofPropertyTyped propertyType: TypeDescription, isRename: Bool) -> TypeDescription {
		let unwrappedType = propertyType.unwrapped
		guard !isRename,
		      case let .simple(_, generics) = unwrappedType,
		      let builtTypeIndex = builtTypeIndex(of: unwrappedType.propertyType),
		      builtTypeIndex < generics.count
		else {
			return unwrappedType
		}
		return generics[builtTypeIndex]
	}

	/// Whether `type` is spelled as an existential that has no initializer: with `any`, or as a composition (`P & Q`).
	private static func isExistentialWithoutInitializer(_ type: TypeDescription) -> Bool {
		switch type {
		case .any, .composition:
			true
		case .array, .attributed, .closure, .dictionary, .implicitlyUnwrappedOptional, .metatype, .nested, .optional, .simple, .some, .tuple, .unknown, .variadic, .void:
			false
		}
	}

	/// Whether `type` is spelled as a function type, optional or with attributes, such as `(@Sendable () -> Secret)?`.
	private static func isFunctionType(_ type: TypeDescription) -> Bool {
		switch type {
		case .closure:
			true
		case let .attributed(type, _, _),
		     let .optional(type):
			isFunctionType(type)
		case .any, .array, .composition, .dictionary, .implicitlyUnwrappedOptional, .metatype, .nested, .simple, .some, .tuple, .unknown, .variadic, .void:
			false
		}
	}

	/// `arguments`, the arguments of an `@Instantiated` or `@Received` attribute, without `erasedToConcreteExistential:`.
	private static func removingErasedToConcreteExistential(from arguments: LabeledExprListSyntax) -> LabeledExprListSyntax {
		let isErasedToConcreteExistential: (LabeledExprSyntax) -> Bool = { $0.label?.text == "erasedToConcreteExistential" }
		var remainingArguments = arguments.filter { !isErasedToConcreteExistential($0) }
		// The argument before a removed last argument takes the removed argument's trailing comma, which is usually none.
		if let lastArgument = arguments.last,
		   isErasedToConcreteExistential(lastArgument),
		   let lastRemainingIndex = remainingArguments.indices.last
		{
			remainingArguments[lastRemainingIndex].trailingComma = lastArgument.trailingComma
		}
		return remainingArguments
	}

	/// `type` with every optional spelling around it removed (`X?`, `X!`, and `Optional<X>`), or `nil` when it is
	/// not optional. The result keeps `type`'s surrounding trivia.
	private static func withoutOptionality(_ type: TypeSyntax) -> TypeSyntax? {
		let wrappedType: TypeSyntax? = if let optionalType = OptionalTypeSyntax(type) {
			optionalType.wrappedType
		} else if let implicitlyUnwrappedOptionalType = ImplicitlyUnwrappedOptionalTypeSyntax(type) {
			implicitlyUnwrappedOptionalType.wrappedType
		} else if let identifierType = IdentifierTypeSyntax(type),
		          identifierType.name.text == "Optional",
		          let genericArguments = identifierType.genericArgumentClause?.arguments,
		          genericArguments.count == 1
		{
			genericArguments.first.flatMap { TypeSyntax($0.argument) }
		} else {
			nil
		}
		guard let wrappedType else {
			return nil
		}
		let unwrappedType = wrappedType
			.with(\.leadingTrivia, type.leadingTrivia)
			.with(\.trailingTrivia, type.trailingTrivia)
		return withoutOptionality(unwrappedType) ?? unwrappedType
	}

	// MARK: - InjectableDeprecation

	/// A use of a SafeDI macro that still works and that SafeDI 3.0 rejects. A warning without a fix-it, since the
	/// replacement changes how the value reaches the type.
	private struct InjectableDeprecation: DiagnosticMessage {
		/// `@Forwarded` on a property whose type is the SafeDI wrapper named `wrapperTypeName`, optional or not.
		static func forwardedWrapper(wrapperTypeName: String) -> Self {
			let article = wrapperTypeName.first.map { "AEIOU".contains($0) } == true ? "an" : "a"
			return Self(
				id: "forwardedWrapper",
				message: "`@Forwarded` on \(article) `\(wrapperTypeName)` property is deprecated and will be an error in SafeDI 3.0: declare it `@Instantiated` on this type, or receive it with `@Received` from an ancestor that declares it, or forward the value it builds.",
			)
		}

		private init(id: String, message: String) {
			diagnosticID = MessageID(domain: "\(Self.self)", id: id)
			self.message = message
		}

		let diagnosticID: MessageID
		let message: String
		let severity = DiagnosticSeverity.warning
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
		/// A rename with `erasedToConcreteExistential: true` into the SafeDI wrapper named `wrapperTypeName`, whose
		/// initializers take a function, of a dependency not spelled as a function.
		case erasedRenameIntoWrapper(wrapperTypeName: String)
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
			case let .erasedRenameIntoWrapper(wrapperTypeName):
				"`erasedToConcreteExistential: true` passes the renamed dependency to a no-label initializer of the property’s type, and `\(wrapperTypeName)`’s initializer takes a closure that builds the value, not an instance. Erase where the wrapper is instantiated, with `@Instantiated(fulfilledByType:erasedToConcreteExistential:)`, and receive the erased wrapper, or erase into a type whose initializer takes the dependency."
			case .erasedInstantiatorUsedWithoutFulfilledByType:
				"An @Instantiated `ErasedInstantiator` or `SendableErasedInstantiator` property must name the type it builds with the argument `fulfilledByType`, such as `@Instantiated(fulfilledByType: \"DefaultService\")`. Use an `Instantiator` or `SendableInstantiator` when the property’s type is the type it builds."
			case .onlyIfAvailableInvalidType:
				"The argument `onlyIfAvailable` must be a Bool literal (`true` or `false`)."
			}
		}
	}
}
