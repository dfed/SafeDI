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

import SafeDICore
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct InstantiableMacro: MemberMacro {
	public static func expansion(
		of node: AttributeSyntax,
		providingMembersOf declaration: some DeclGroupSyntax,
		conformingTo _: [TypeSyntax],
		in context: some MacroExpansionContext
	) throws -> [DeclSyntax] {
		if let fulfillingAdditionalTypesArgument = declaration
			.attributes
			.instantiableMacro?
			.fulfillingAdditionalTypes
		{
			if let arrayExpression = ArrayExprSyntax(fulfillingAdditionalTypesArgument) {
				if arrayExpression
					.elements
					.contains(where: \.expression.typeDescription.isOptional)
				{
					throw InstantiableError.fulfillingAdditionalTypesContainsOptional
				}
			} else {
				throw InstantiableError.fulfillingAdditionalTypesArgumentInvalid
			}
		}

		if let concreteDeclaration: ConcreteDeclSyntaxProtocol
			= ActorDeclSyntax(declaration)
			?? ClassDeclSyntax(declaration)
			?? StructDeclSyntax(declaration)
		{
			lazy var extendsInstantiable = concreteDeclaration.inheritanceClause?.inheritedTypes.contains(where: \.type.typeDescription.isInstantiable) ?? false
			let mustExtendInstantiable = if let conformsElsewhereArgument = declaration.attributes.instantiableMacro?.conformsElsewhere,
			                                let boolExpression = BooleanLiteralExprSyntax(conformsElsewhereArgument)
			{
				boolExpression.literal.tokenKind == .keyword(.false)
			} else {
				true
			}

			if mustExtendInstantiable, !extendsInstantiable {
				var modifiedDeclaration = concreteDeclaration
				var inheritedType = InheritedTypeSyntax(
					type: IdentifierTypeSyntax(name: .identifier("Instantiable"))
				)
				if let existingInheritanceClause = modifiedDeclaration.inheritanceClause {
					inheritedType.trailingTrivia = .space
					modifiedDeclaration.inheritanceClause?.inheritedTypes = existingInheritanceClause.inheritedTypes.map { inhertiedType in
						var modifiedInhertiedType = inhertiedType
						if modifiedInhertiedType.trailingComma == nil {
							modifiedInhertiedType.trailingComma = .commaToken(trailingTrivia: .space)
							modifiedInhertiedType.type.trailingTrivia = []
						}
						return modifiedInhertiedType
					} + [inheritedType]
				} else {
					modifiedDeclaration.name.trailingTrivia = []
					modifiedDeclaration.inheritanceClause = InheritanceClauseSyntax(
						colon: .colonToken(trailingTrivia: .space),
						inheritedTypes: InheritedTypeListSyntax(arrayLiteral: InheritedTypeSyntax(
							type: IdentifierTypeSyntax(name: .identifier("Instantiable"))
						)),
						trailingTrivia: .space
					)
				}
				context.diagnose(Diagnostic(
					node: node,
					error: FixableInstantiableError.missingInstantiableConformance,
					changes: [
						.replace(
							oldNode: Syntax(concreteDeclaration),
							newNode: Syntax(modifiedDeclaration)
						),
					]
				))
			}

			let visitor = InstantiableVisitor(declarationType: .concreteDecl)
			visitor.walk(concreteDeclaration)
			for diagnostic in visitor.diagnostics {
				context.diagnose(diagnostic)
			}

			if visitor.isRoot, let instantiableType = visitor.instantiableType {
				let inheritedDependencies = visitor.dependencies.filter {
					switch $0.source {
					case let .aliased(fulfillingProperty, _, _):
						// Aliased properties must not be inherited from elsewhere.
						!visitor.dependencies.contains { $0.property == fulfillingProperty }
					case .instantiated:
						false
					case .forwarded, .received:
						true
					}
				}
				guard inheritedDependencies.isEmpty else {
					throw InstantiableError.cannotBeRoot(
						instantiableType,
						violatingDependencies: inheritedDependencies
					)
				}
			}

			let forwardedProperties = visitor
				.dependencies
				.filter { $0.source == .forwarded }
				.map(\.property)
			let hasMemberwiseInitializerForInjectableProperties = visitor
				.initializers
				.contains(where: { $0.isValid(forFulfilling: visitor.dependencies) })
			guard hasMemberwiseInitializerForInjectableProperties else {
				func associatedError(for initializer: Initializer) -> (initializer: Initializer, syntax: InitializerDeclSyntax, error: Initializer.FixableError)? {
					do {
						try initializer.validate(fulfilling: visitor.dependencies)
					} catch {
						if let fixableError = error.asFixableError, let syntax = visitor.initializerToInitSyntaxMap[initializer] {
							return (initializer: initializer, syntax: syntax, error: fixableError)
						}
					}
					return nil
				}
				let initializerToFix: (initializer: Initializer, syntax: InitializerDeclSyntax, error: Initializer.FixableError)? = visitor.initializers.compactMap {
					associatedError(for: $0)
				}.sorted {
					$0.error < $1.error
				}.first

				if let initializerToFix {
					let syntaxToFix = initializerToFix.syntax
					switch initializerToFix.error.asErrorToFix {
					case let .missingArguments(missingArguments):
						var fixedSyntax = syntaxToFix
						let existingArgumentCount = syntaxToFix.signature.parameterClause.parameters.count
						let firstArgumentLeadingTrivia: Trivia = if existingArgumentCount > 1 {
							syntaxToFix.signature.parameterClause.parameters.first?.leadingTrivia ?? []
						} else if existingArgumentCount + missingArguments.count > 1 {
							.newline
						} else {
							[]
						}
						let firstArgumentTrailingComma: TokenSyntax? = if existingArgumentCount > 1 {
							syntaxToFix.signature.parameterClause.parameters.first?.trailingComma
						} else if existingArgumentCount + missingArguments.count > 1 {
							.commaToken(trailingTrivia: .newline)
						} else {
							.commaToken()
						}
						let lastArgumentLeadingTrivia = syntaxToFix.signature.parameterClause.parameters.last?.leadingTrivia ?? []
						let lastArgumentTrailingTrivia: Trivia = if existingArgumentCount > 1 {
							syntaxToFix.signature.parameterClause.parameters.last?.trailingTrivia ?? .newline
						} else if existingArgumentCount + missingArguments.count > 1 {
							.newline
						} else {
							[]
						}
						let properties = visitor.dependencies.map(\.property)

						var existingParameters = fixedSyntax.signature.parameterClause.parameters.reduce(into: [Property: FunctionParameterSyntax]()) { partialResult, next in
							partialResult[Initializer.Argument(next).asProperty] = next
						}
						fixedSyntax.signature.parameterClause.parameters = []
						func normalizeFunctionParameter(_ parameter: FunctionParameterSyntax, for property: Property) -> FunctionParameterSyntax {
							var parameter = parameter
							if let indexOfDependency = properties.firstIndex(of: property) {
								parameter.leadingTrivia = if indexOfDependency == 0 {
									firstArgumentLeadingTrivia
								} else if existingArgumentCount != 1 {
									lastArgumentLeadingTrivia
								} else {
									[]
								}
								parameter.trailingTrivia = []
							}
							return parameter
						}
						for property in properties {
							let functionArgumentProperty = Property(
								label: property.label,
								typeDescription: property.typeDescription.asFunctionParameter
							)
							if let existingParameter = existingParameters[functionArgumentProperty] {
								fixedSyntax.signature.parameterClause.parameters.append(
									normalizeFunctionParameter(existingParameter, for: functionArgumentProperty)
								)
							} else {
								fixedSyntax.signature.parameterClause.parameters.append(
									normalizeFunctionParameter(property.asFunctionParamter, for: functionArgumentProperty)
								)
							}
							existingParameters[functionArgumentProperty] = nil
						}

						for existingParameter in existingParameters.map(\.value) {
							if let priorIndex = syntaxToFix.signature.parameterClause.parameters.firstIndex(of: existingParameter) {
								fixedSyntax.signature.parameterClause.parameters.insert(
									existingParameter,
									at: fixedSyntax.signature.parameterClause.parameters.index(
										priorIndex,
										offsetBy: priorIndex == syntaxToFix.signature.parameterClause.parameters.startIndex ? 0 : missingArguments.count
									)
								)
							}
						}

						let lastParameter = fixedSyntax.signature.parameterClause.parameters.last
						fixedSyntax.signature.parameterClause.parameters = .init(fixedSyntax.signature.parameterClause.parameters.map { parameter in
							var parameter = parameter
							if parameter == lastParameter {
								parameter.trailingComma = nil
								parameter.trailingTrivia = lastArgumentTrailingTrivia
							} else {
								parameter.trailingComma = firstArgumentTrailingComma
							}
							return parameter
						})
						fixedSyntax.signature.parameterClause.rightParen.leadingTrivia = .init(pieces: fixedSyntax.signature.parameterClause.rightParen.leadingTrivia.pieces.filter {
							if lastArgumentTrailingTrivia.contains(where: \.isNewline) {
								!$0.isNewline
							} else {
								true
							}
						})

						if let body = fixedSyntax.body {
							let propertyLabelToPropertyMap = properties.reduce(into: [String: Property]()) { partialResult, next in
								partialResult[next.label] = next
							}

							var existingPropertyAssignment = [Property: CodeBlockItemSyntax]()
							var nonPropertyAssignmentStatements = [CodeBlockItemSyntax]()
							for statement in body.statements {
								// Ideally we'd check if this is an `InfixOperatorExprSyntax`, but Xcode 16.4 doesn't parse this properly.
								// Instead, the macro receives `ExprListSyntax` when running inside Xcode.
								// Checking the description isn't ideal, but it's close enough for our purposes today.
//								if let infixOperatorExpression = InfixOperatorExprSyntax(statement.item),
//								   let memberAcessExpression = MemberAccessExprSyntax(infixOperatorExpression.leftOperand),
//								   DeclReferenceExprSyntax(memberAcessExpression.base)?.baseName.text == TokenSyntax.keyword(.`self`).text,
//								   let property = propertyLabelToPropertyMap[memberAcessExpression.declName.baseName.text]
								let splitStatement = statement.item.trimmed.description.split { $0 == "." || $0 == " " }
								if splitStatement.count > 2,
								   splitStatement[0] == "self",
								   splitStatement[2] == "=",
								   let property = propertyLabelToPropertyMap[String(splitStatement[1])]
								{
									existingPropertyAssignment[property] = statement
								} else {
									nonPropertyAssignmentStatements.append(statement)
								}
							}

							let propertyAssignments = properties.map {
								if let existingAssignment = existingPropertyAssignment[$0] {
									return existingAssignment
								} else {
									var propertyAssignment = $0.asPropertyAssignment()
									propertyAssignment.leadingTrivia = body.statements.first?.leadingTrivia ?? []
									return propertyAssignment
								}
							}

							fixedSyntax.body?.statements = propertyAssignments + .init(nonPropertyAssignmentStatements)
						}

						context.diagnose(Diagnostic(
							node: Syntax(syntaxToFix),
							error: FixableInstantiableError.missingRequiredInitializer(.missingArguments(missingArguments)),
							changes: [
								.replace(
									oldNode: Syntax(syntaxToFix),
									newNode: Syntax(fixedSyntax)
								),
							]
						))

					case .inaccessibleInitializer:
						let disallowedModifiers = Set([
							"private",
							"fileprivate",
							"internal",
							"package",
						])
						var fixedSyntax = syntaxToFix
						fixedSyntax.modifiers = .init(fixedSyntax.modifiers.map {
							if disallowedModifiers.contains($0.name.text) {
								.init(
									leadingTrivia: $0.leadingTrivia,
									name: TokenSyntax(
										TokenKind.keyword(.public),
										presence: .present
									),
									trailingTrivia: $0.trailingTrivia
								)
							} else {
								$0
							}
						})
						if !fixedSyntax.modifiers.containsPublicOrOpen {
							if syntaxToFix.modifiers.first != nil {
								fixedSyntax.modifiers[fixedSyntax.modifiers.startIndex].leadingTrivia = []
							}
							fixedSyntax.modifiers.insert(.init(
								leadingTrivia: fixedSyntax.modifiers.isEmpty ? .newline : [],
								name: TokenSyntax(
									TokenKind.keyword(.public),
									presence: .present
								),
								trailingTrivia: .space
							), at: fixedSyntax.modifiers.startIndex)
						}
						if let firstModifier = syntaxToFix.modifiers.first {
							fixedSyntax.modifiers[fixedSyntax.modifiers.startIndex].leadingTrivia = firstModifier.leadingTrivia
						} else {
							fixedSyntax.modifiers[fixedSyntax.modifiers.startIndex].leadingTrivia = fixedSyntax.initKeyword.leadingTrivia
							fixedSyntax.initKeyword.leadingTrivia = []
						}
						context.diagnose(Diagnostic(
							node: Syntax(syntaxToFix),
							error: FixableInstantiableError.missingRequiredInitializer(.isNotPublicOrOpen),
							changes: [
								.replace(
									oldNode: Syntax(syntaxToFix),
									newNode: Syntax(fixedSyntax)
								),
							]
						))
					}
				} else {
					var declarationWithInitializer = declaration
					declarationWithInitializer.memberBlock.members.insert(
						MemberBlockItemSyntax(
							leadingTrivia: .newline,
							decl: Initializer.generateRequiredInitializer(
								for: visitor.dependencies,
								declarationType: concreteDeclaration.declType,
								andAdditionalPropertiesWithLabels: visitor.uninitializedNonOptionalPropertyNames
							),
							trailingTrivia: .newline
						),
						at: declarationWithInitializer.memberBlock.members.startIndex
					)
					let errorType: FixableInstantiableError.MissingInitializer = if visitor.uninitializedNonOptionalPropertyNames.isEmpty {
						.hasOnlyInjectableProperties
					} else if visitor.dependencies.isEmpty {
						.hasNoInjectableProperties
					} else {
						.hasInjectableAndNotInjectableProperties
					}
					context.diagnose(Diagnostic(
						node: Syntax(declaration.memberBlock),
						error: FixableInstantiableError.missingRequiredInitializer(errorType),
						changes: [
							.replace(
								oldNode: Syntax(declaration),
								newNode: Syntax(declarationWithInitializer)
							),
						]
					))
				}
				return []
			}
			return generateForwardedProperties(from: forwardedProperties)

		} else if let extensionDeclaration = ExtensionDeclSyntax(declaration) {
			lazy var extendsInstantiable = extensionDeclaration.inheritanceClause?.inheritedTypes.contains(where: \.type.typeDescription.isInstantiable) ?? false
			let mustExtendInstantiable = if let conformsElsewhereArgument = declaration.attributes.instantiableMacro?.conformsElsewhere,
			                                let boolExpression = BooleanLiteralExprSyntax(conformsElsewhereArgument)
			{
				boolExpression.literal.tokenKind == .keyword(.false)
			} else {
				true
			}

			if mustExtendInstantiable, !extendsInstantiable {
				var modifiedDeclaration = extensionDeclaration
				var inheritedType = InheritedTypeSyntax(
					type: IdentifierTypeSyntax(name: .identifier("Instantiable"))
				)
				if let existingInheritanceClause = modifiedDeclaration.inheritanceClause {
					inheritedType.trailingTrivia = .space
					modifiedDeclaration.inheritanceClause?.inheritedTypes = existingInheritanceClause.inheritedTypes.map { inhertiedType in
						var modifiedInhertiedType = inhertiedType
						if modifiedInhertiedType.trailingComma == nil {
							modifiedInhertiedType.trailingComma = .commaToken(trailingTrivia: .space)
							modifiedInhertiedType.type.trailingTrivia = []
						}
						return modifiedInhertiedType
					} + [inheritedType]
				} else {
					modifiedDeclaration.extendedType.trailingTrivia = []
					modifiedDeclaration.inheritanceClause = InheritanceClauseSyntax(
						colon: .colonToken(trailingTrivia: .space),
						inheritedTypes: InheritedTypeListSyntax(arrayLiteral: InheritedTypeSyntax(
							type: IdentifierTypeSyntax(name: .identifier("Instantiable"))
						)),
						trailingTrivia: .space
					)
				}
				context.diagnose(Diagnostic(
					node: node,
					error: FixableInstantiableError.missingInstantiableConformance,
					changes: [
						.replace(
							oldNode: Syntax(extensionDeclaration),
							newNode: Syntax(modifiedDeclaration)
						),
					]
				))
			}
			if extensionDeclaration.genericWhereClause != nil {
				var modifiedDeclaration = extensionDeclaration
				modifiedDeclaration.genericWhereClause = nil
				context.diagnose(Diagnostic(
					node: node,
					error: FixableInstantiableError.disallowedGenericWhereClause,
					changes: [
						.replace(
							oldNode: Syntax(extensionDeclaration),
							newNode: Syntax(modifiedDeclaration)
						),
					]
				))
			}

			let visitor = InstantiableVisitor(declarationType: .extensionDecl)
			visitor.walk(extensionDeclaration)
			for diagnostic in visitor.diagnostics {
				context.diagnose(diagnostic)
			}

			if visitor.isRoot, let instantiableType = visitor.instantiableType {
				guard visitor.instantiables.flatMap(\.dependencies).isEmpty else {
					throw InstantiableError.cannotBeRoot(
						instantiableType,
						violatingDependencies: visitor.instantiables.flatMap(\.dependencies)
					)
				}
			}

			let instantiables = visitor.instantiables
			if instantiables.count > 1 {
				var concreteInstantiables = Set<TypeDescription>()
				for concreteInstantiable in instantiables.map(\.concreteInstantiable) {
					if concreteInstantiables.contains(concreteInstantiable) {
						throw InstantiableError.tooManyInstantiateMethods(concreteInstantiable)
					} else {
						concreteInstantiables.insert(concreteInstantiable)
					}
				}
			} else if instantiables.isEmpty {
				let extendedTypeName = extensionDeclaration.extendedType.typeDescription.asSource
				var membersWithInitializer = declaration.memberBlock.members
				membersWithInitializer.insert(
					MemberBlockItemSyntax(
						leadingTrivia: .newline,
						decl: FunctionDeclSyntax(
							modifiers: DeclModifierListSyntax(
								arrayLiteral: DeclModifierSyntax(
									name: TokenSyntax(
										TokenKind.keyword(.public),
										presence: .present
									),
									trailingTrivia: .space
								),
								DeclModifierSyntax(
									name: TokenSyntax(
										TokenKind.keyword(.static),
										presence: .present
									),
									trailingTrivia: .space
								)
							),
							name: TokenSyntax(
								TokenKind.identifier(InstantiableVisitor.instantiateMethodName),
								leadingTrivia: .space,
								presence: .present
							),
							signature: FunctionSignatureSyntax(
								parameterClause: FunctionParameterClauseSyntax(
									parameters: FunctionParameterListSyntax([])
								),
								returnClause: ReturnClauseSyntax(
									arrow: .arrowToken(
										leadingTrivia: .space,
										trailingTrivia: .space
									),
									type: IdentifierTypeSyntax(
										name: .identifier(extendedTypeName)
									)
								)
							),
							body: CodeBlockSyntax(
								leadingTrivia: .newline,
								statements: CodeBlockItemListSyntax([]),
								trailingTrivia: .newline
							)
						),
						trailingTrivia: .newline
					),
					at: membersWithInitializer.startIndex
				)
				context.diagnose(Diagnostic(
					node: Syntax(extensionDeclaration.memberBlock.members),
					error: FixableInstantiableError.missingRequiredInstantiateMethod(
						typeName: extendedTypeName
					),
					changes: [
						.replace(
							oldNode: Syntax(declaration.memberBlock.members),
							newNode: Syntax(membersWithInitializer)
						),
					]
				))
			}
			return []
		} else {
			throw InstantiableError.decoratingIncompatibleType
		}
	}

	private static func generateForwardedProperties(
		from forwardedProperties: [Property]
	) -> [DeclSyntax] {
		if forwardedProperties.isEmpty {
			[]
		} else if forwardedProperties.count == 1, let forwardedProperty = forwardedProperties.first {
			[
				DeclSyntax(
					TypeAliasDeclSyntax(
						modifiers: DeclModifierListSyntax(
							arrayLiteral: DeclModifierSyntax(
								name: TokenSyntax(
									TokenKind.keyword(.public),
									presence: .present
								),
								trailingTrivia: .space
							)
						),
						name: .identifier("ForwardedProperties"),
						initializer: TypeInitializerClauseSyntax(
							value: IdentifierTypeSyntax(
								name: .identifier(forwardedProperty.typeDescription.asSource)
							)
						)
					)
				),
			]
		} else {
			[
				DeclSyntax(
					TypeAliasDeclSyntax(
						modifiers: DeclModifierListSyntax(
							arrayLiteral: DeclModifierSyntax(
								name: TokenSyntax(
									TokenKind.keyword(.public),
									presence: .present
								),
								trailingTrivia: .space
							)
						),
						name: .identifier("ForwardedProperties"),
						initializer: TypeInitializerClauseSyntax(value: forwardedProperties.asTuple)
					)
				),
			]
		}
	}

	// MARK: - InstantiableError

	private enum InstantiableError: Error, CustomStringConvertible {
		case decoratingIncompatibleType
		case fulfillingAdditionalTypesContainsOptional
		case fulfillingAdditionalTypesArgumentInvalid
		case tooManyInstantiateMethods(TypeDescription)
		case cannotBeRoot(TypeDescription, violatingDependencies: [Dependency])

		var description: String {
			switch self {
			case .decoratingIncompatibleType:
				"@\(InstantiableVisitor.macroName) must decorate an extension on a type or a class, struct, or actor declaration"
			case .fulfillingAdditionalTypesContainsOptional:
				"The argument `fulfillingAdditionalTypes` must not include optionals"
			case .fulfillingAdditionalTypesArgumentInvalid:
				"The argument `fulfillingAdditionalTypes` must be an inlined array"
			case let .tooManyInstantiateMethods(type):
				"@\(InstantiableVisitor.macroName)-decorated extension must have a single `\(InstantiableVisitor.instantiateMethodName)(…)` method that returns `\(type.asSource)`"
			case let .cannotBeRoot(declaredRootType, violatingDependencies):
				"""
				Types decorated with `@\(InstantiableVisitor.macroName)(isRoot: true)` must only have dependencies that are all `@\(Dependency.Source.instantiatedRawValue)` or `@\(Dependency.Source.receivedRawValue)(fulfilledByDependencyNamed:ofType:)`, where the latter properties can be fulfilled by `@\(Dependency.Source.instantiatedRawValue)` or `@\(Dependency.Source.receivedRawValue)(fulfilledByDependencyNamed:ofType:)` properties declared on this type.

				The following dependencies were found on \(declaredRootType.asSource) that violated this contract:
				\(violatingDependencies.map(\.property.asSource).joined(separator: "\n"))
				"""
			}
		}
	}
}

// MARK: - TypeDescription

extension TypeDescription {
	fileprivate var isInstantiable: Bool {
		self == .simple(name: "Instantiable")
			|| self == .nested(
				name: "Instantiable",
				parentType: .simple(name: "SafeDI")
			)
			|| self == .attributed(
				.simple(name: "Instantiable"),
				specifiers: nil,
				attributes: ["retroactive"]
			)
			|| self == .nested(
				name: "Instantiable",
				parentType: .attributed(
					.simple(name: "SafeDI"),
					specifiers: nil,
					attributes: ["retroactive"]
				)
			)
	}
}

// MARK: Initializer

extension Initializer {
	fileprivate enum FixableError: Comparable, Hashable, Sendable {
		case inaccessibleInitializer
		case missingArguments([Property])
		indirect case multiple([FixableError])

		// Compare in terms of delta from what SafeDI needs – smallest requires the smallest change to make satisfactory.
		fileprivate static func < (lhs: FixableError, rhs: FixableError) -> Bool {
			switch (lhs, rhs) {
			case (.inaccessibleInitializer, _):
				lhs != rhs
			case let (.missingArguments(lhs), .missingArguments(rhs)):
				lhs.count < rhs.count
			case (.missingArguments, _):
				lhs != rhs
			case let (.multiple(lhs), .multiple(rhs)):
				lhs.count < rhs.count
			case (.multiple, _):
				false
			}
		}

		fileprivate enum ErrorToFix {
			case inaccessibleInitializer
			case missingArguments([Property])
		}

		fileprivate var asErrorToFix: ErrorToFix {
			switch self {
			case .inaccessibleInitializer:
				.inaccessibleInitializer
			case let .missingArguments(arguments):
				.missingArguments(arguments)
			case let .multiple(errors):
				errors.sorted().first!.asErrorToFix
			}
		}
	}
}

// MARK: Initializer.GenerationError

extension Initializer.GenerationError {
	fileprivate var asFixableError: Initializer.FixableError? {
		switch self {
		case let .missingArguments(arguments):
			.missingArguments(arguments)
		case .inaccessibleInitializer:
			.inaccessibleInitializer
		case let .multiple(errors):
			.multiple(errors.compactMap(\.asFixableError))
		case .asyncInitializer,
		     .genericParameterInInitializer,
		     .optionalInitializer,
		     .throwingInitializer,
		     .unexpectedArgument,
		     .whereClauseOnInitializer:
			nil
		}
	}
}
