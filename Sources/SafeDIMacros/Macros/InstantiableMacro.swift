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
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct InstantiableMacro: MemberMacro {
	public static func expansion(
		of node: AttributeSyntax,
		providingMembersOf declaration: some DeclGroupSyntax,
		conformingTo _: [TypeSyntax],
		in context: some MacroExpansionContext,
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

		if let mockAttributesArgument = declaration
			.attributes
			.instantiableMacro?
			.mockAttributes
		{
			if StringLiteralExprSyntax(mockAttributesArgument) == nil {
				throw InstantiableError.mockAttributesArgumentInvalid
			}
		}

		if let generateMockArgument = declaration
			.attributes
			.instantiableMacro?
			.generateMock
		{
			if BooleanLiteralExprSyntax(generateMockArgument) == nil {
				throw InstantiableError.generateMockArgumentInvalid
			}
		}

		if let customMockNameArgument = declaration
			.attributes
			.instantiableMacro?
			.customMockName
		{
			if NilLiteralExprSyntax(customMockNameArgument) == nil,
			   StringLiteralExprSyntax(customMockNameArgument) == nil
			{
				throw InstantiableError.customMockNameArgumentInvalid
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
					type: IdentifierTypeSyntax(name: .identifier("Instantiable")),
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
							type: IdentifierTypeSyntax(name: .identifier("Instantiable")),
						)),
						trailingTrivia: .space,
					)
				}
				context.diagnose(Diagnostic(
					node: node,
					error: FixableInstantiableError.missingInstantiableConformance,
					changes: [
						.replace(
							oldNode: Syntax(concreteDeclaration),
							newNode: Syntax(modifiedDeclaration),
						),
					],
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
						violatingDependencies: inheritedDependencies,
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
							let functionParameterProperty = property.asFunctionParamter
							if let existingParameter = existingParameters[functionParameterProperty] {
								fixedSyntax.signature.parameterClause.parameters.append(
									normalizeFunctionParameter(existingParameter, for: functionParameterProperty),
								)
							} else {
								fixedSyntax.signature.parameterClause.parameters.append(
									normalizeFunctionParameter(property.asFunctionParamterSyntax, for: functionParameterProperty),
								)
							}
							existingParameters[functionParameterProperty] = nil
						}

						for existingParameter in existingParameters.map(\.value) {
							if let priorIndex = syntaxToFix.signature.parameterClause.parameters.firstIndex(of: existingParameter) {
								fixedSyntax.signature.parameterClause.parameters.insert(
									existingParameter,
									at: fixedSyntax.signature.parameterClause.parameters.index(
										priorIndex,
										offsetBy: priorIndex == syntaxToFix.signature.parameterClause.parameters.startIndex ? 0 : missingArguments.count,
									),
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
									if let leadingTrivia = body.statements.first?.leadingTrivia {
										propertyAssignment.leadingTrivia = leadingTrivia
									}
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
									newNode: Syntax(fixedSyntax),
								),
							],
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
										presence: .present,
									),
									trailingTrivia: $0.trailingTrivia,
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
									presence: .present,
								),
								trailingTrivia: .space,
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
									newNode: Syntax(fixedSyntax),
								),
							],
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
								andAdditionalPropertiesWithLabels: visitor.uninitializedNonOptionalPropertyNames,
							),
							trailingTrivia: .newline,
						),
						at: declarationWithInitializer.memberBlock.members.startIndex,
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
								newNode: Syntax(declarationWithInitializer),
							),
						],
					))
				}
				return []
			}
			// Emit diagnostics for duplicate mock() methods.
			for duplicateMockSyntax in visitor.duplicateMockFunctionSyntaxes {
				context.diagnose(Diagnostic(
					node: Syntax(duplicateMockSyntax),
					error: FixableInstantiableError.duplicateMockMethod,
					changes: [
						.replace(
							oldNode: Syntax(duplicateMockSyntax),
							newNode: Syntax("" as DeclSyntax),
						),
					],
				))
			}

			// Validate customMockName: requires generateMock: true.
			if let instantiableMacro = declaration.attributes.instantiableMacro {
				let customMockNameValue = instantiableMacro.customMockNameValue
				if customMockNameValue != nil,
				   !instantiableMacro.generateMockValue,
				   let macroArguments = instantiableMacro.arguments,
				   let arguments = LabeledExprListSyntax(macroArguments),
				   let customMockNameIndex = arguments.firstIndex(where: { $0.label?.text == "customMockName" })
				{
					context.diagnose(Diagnostic(
						node: Syntax(instantiableMacro),
						error: FixableInstantiableError.customMockNameWithoutGenerateMock,
						changes: Self.addGenerateMockArgument(to: instantiableMacro, arguments: arguments, customMockNameOffset: arguments.distance(from: arguments.startIndex, to: customMockNameIndex), on: declaration),
					))
				}
				// When generateMock: true and a method named "mock" exists (not custom-named), it must be renamed.
				if instantiableMacro.generateMockValue,
				   customMockNameValue == nil,
				   let mockSyntax = visitor.mockFunctionSyntax
				{
					context.diagnose(Diagnostic(
						node: Syntax(mockSyntax),
						error: FixableInstantiableError.mockMethodNeedsCustomName,
						changes: Self.renameMethodToCustomMock(mockSyntax: mockSyntax, instantiableMacro: instantiableMacro, on: declaration),
					))
				}
				// When customMockName is set and a literal "mock" method also exists, it conflicts with the generated mock.
				if instantiableMacro.generateMockValue,
				   customMockNameValue != nil,
				   let conflictingMock = visitor.conflictingMockFunctionSyntax
				{
					context.diagnose(Diagnostic(
						node: Syntax(conflictingMock),
						error: FixableInstantiableError.mockMethodConflictsWithGeneratedMock,
						changes: [
							.replace(
								oldNode: Syntax(conflictingMock),
								newNode: Syntax("" as DeclSyntax),
							),
						],
					))
				}
				// When customMockName is set but no method with that name is found, emit error.
				if let customMockNameValue,
				   instantiableMacro.generateMockValue,
				   visitor.mockFunctionSyntax == nil
				{
					context.diagnose(Diagnostic(
						node: Syntax(instantiableMacro),
						error: FixableInstantiableError.customMockNameMethodNotFound(customMockNameValue),
						changes: Self.generateCustomMockStub(
							named: customMockNameValue,
							typeName: concreteDeclaration.name.text,
							dependencies: visitor.dependencies,
							on: declaration,
						),
					))
				}
			}

			// Validate mock method if one exists: must be public, return Self or the type name, and have parameters for all dependencies.
			if let mockInitializer = visitor.mockInitializer,
			   let mockSyntax = visitor.mockFunctionSyntax
			{
				// Check that non-dependency parameters have default values.
				let dependencyLabels = Set(visitor.dependencies.map(\.property.label))
				let nonDependenciesWithoutDefaults = mockInitializer.arguments
					.filter { !dependencyLabels.contains($0.innerLabel) && !$0.hasDefaultValue }
					.map(\.asProperty)
				if !nonDependenciesWithoutDefaults.isEmpty {
					let nonDependencyLabelsWithoutDefaults = Set(nonDependenciesWithoutDefaults.map(\.label))
					var fixedMockSyntax = mockSyntax
					fixedMockSyntax.signature.parameterClause.parameters = FunctionParameterListSyntax(
						mockSyntax.signature.parameterClause.parameters.map { parameter in
							var fixedParameter = parameter
							let parameterLabel = parameter.secondName?.text ?? parameter.firstName.text
							if nonDependencyLabelsWithoutDefaults.contains(parameterLabel),
							   fixedParameter.defaultValue == nil
							{
								fixedParameter.defaultValue = InitializerClauseSyntax(
									equal: .equalToken(leadingTrivia: .space, trailingTrivia: .space),
									value: EditorPlaceholderExprSyntax(placeholder: .identifier("<#default#>")),
								)
							}
							return fixedParameter
						},
					)
					context.diagnose(Diagnostic(
						node: Syntax(mockSyntax),
						error: FixableInstantiableError.mockMethodNonDependencyMissingDefaultValue(nonDependenciesWithoutDefaults),
						changes: [
							.replace(
								oldNode: Syntax(mockSyntax),
								newNode: Syntax(fixedMockSyntax),
							),
						],
					))
				}
				let typeName = concreteDeclaration.name.text
				let instantiableTypeStrippingGenerics = visitor.instantiableType?.strippingGenerics
				let mockReturnType = mockSyntax.signature.returnClause?.type.typeDescription
				let additionalTypesStrippingGenerics = (visitor.additionalInstantiables ?? []).map(\.strippingGenerics)
				let isSelfReturnType = mockReturnType == .simple(name: "Self", generics: [])
				let returnTypeMatchesTypeName = isSelfReturnType
					|| mockReturnType?.strippingGenerics == instantiableTypeStrippingGenerics
					|| additionalTypesStrippingGenerics.contains(where: { $0 == mockReturnType?.strippingGenerics })
				if !returnTypeMatchesTypeName {
					var fixedMockSyntax = mockSyntax
					if let existingReturnClause = mockSyntax.signature.returnClause {
						fixedMockSyntax.signature.returnClause = ReturnClauseSyntax(
							arrow: .arrowToken(
								leadingTrivia: existingReturnClause.arrow.leadingTrivia,
								trailingTrivia: existingReturnClause.arrow.trailingTrivia,
							),
							type: IdentifierTypeSyntax(
								leadingTrivia: existingReturnClause.type.leadingTrivia,
								name: .identifier(typeName),
								trailingTrivia: existingReturnClause.type.trailingTrivia,
							),
						)
					} else {
						fixedMockSyntax.signature.parameterClause.rightParen.trailingTrivia = []
						fixedMockSyntax.signature.returnClause = ReturnClauseSyntax(
							arrow: .arrowToken(
								leadingTrivia: .space,
								trailingTrivia: .space,
							),
							type: IdentifierTypeSyntax(
								name: .identifier(typeName),
								trailingTrivia: .space,
							),
						)
					}
					context.diagnose(Diagnostic(
						node: Syntax(mockSyntax),
						error: FixableInstantiableError.mockMethodIncorrectReturnType(typeName: typeName),
						changes: [
							.replace(
								oldNode: Syntax(mockSyntax),
								newNode: Syntax(fixedMockSyntax),
							),
						],
					))
				}
				if !mockInitializer.isPublicOrOpen {
					var fixedMockSyntax = mockSyntax
					// Mock detection requires `static` or `class`, so modifiers.first is always non-nil.
					let firstModifier = mockSyntax.modifiers.first
					fixedMockSyntax.modifiers.insert(
						DeclModifierSyntax(
							leadingTrivia: firstModifier?.leadingTrivia ?? mockSyntax.funcKeyword.leadingTrivia,
							name: .keyword(.public),
							trailingTrivia: .space,
						),
						at: fixedMockSyntax.modifiers.startIndex,
					)
					if let firstModifier {
						fixedMockSyntax.modifiers[fixedMockSyntax.modifiers.startIndex].leadingTrivia = firstModifier.leadingTrivia
						let secondModifierIndex = fixedMockSyntax.modifiers.index(after: fixedMockSyntax.modifiers.startIndex)
						fixedMockSyntax.modifiers[secondModifierIndex].leadingTrivia = []
					}
					context.diagnose(Diagnostic(
						node: Syntax(mockSyntax),
						error: FixableInstantiableError.mockMethodNotPublic,
						changes: [
							.replace(
								oldNode: Syntax(mockSyntax),
								newNode: Syntax(fixedMockSyntax),
							),
						],
					))
				}
				if !visitor.dependencies.isEmpty {
					do {
						try mockInitializer.validate(fulfilling: visitor.dependencies)
					} catch {
						if let fixableError = error.asFixableError,
						   case let .missingArguments(missingArguments) = fixableError.asErrorToFix
						{
							var fixedSyntax = mockSyntax
							fixedSyntax.signature.parameterClause = Self.buildFixedParameterClause(
								from: mockSyntax.signature.parameterClause,
								requiredProperties: visitor.dependencies.map(\.property),
							)
							context.diagnose(Diagnostic(
								node: Syntax(mockSyntax),
								error: FixableInstantiableError.mockMethodMissingArguments(missingArguments),
								changes: [
									.replace(
										oldNode: Syntax(mockSyntax),
										newNode: Syntax(fixedSyntax),
									),
								],
							))
						}
					}
				}
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
					type: IdentifierTypeSyntax(name: .identifier("Instantiable")),
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
							type: IdentifierTypeSyntax(name: .identifier("Instantiable")),
						)),
						trailingTrivia: .space,
					)
				}
				context.diagnose(Diagnostic(
					node: node,
					error: FixableInstantiableError.missingInstantiableConformance,
					changes: [
						.replace(
							oldNode: Syntax(extensionDeclaration),
							newNode: Syntax(modifiedDeclaration),
						),
					],
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
							newNode: Syntax(modifiedDeclaration),
						),
					],
				))
			}

			let visitor = InstantiableVisitor(declarationType: .extensionDecl)
			visitor.walk(extensionDeclaration)
			for diagnostic in visitor.diagnostics {
				context.diagnose(diagnostic)
			}

			// Validate mock() methods on extensions: must be public, return the extended type or Self, and be unique per return type.
			let extendedTypeDescription = extensionDeclaration.extendedType.typeDescription
			let extendedTypeName = extendedTypeDescription.asSource
			let extendedTypeStrippingGenerics = extendedTypeDescription.strippingGenerics
			var allMockFunctions = [FunctionDeclSyntax]()
			if let firstMock = visitor.mockFunctionSyntax {
				allMockFunctions.append(firstMock)
			}
			allMockFunctions.append(contentsOf: visitor.duplicateMockFunctionSyntaxes)
			let extensionDependencies = visitor.instantiables.flatMap(\.dependencies)
			// Validate customMockName: requires generateMock: true.
			if let instantiableMacro = declaration.attributes.instantiableMacro {
				let customMockNameValue = instantiableMacro.customMockNameValue
				if customMockNameValue != nil,
				   !instantiableMacro.generateMockValue,
				   let macroArguments = instantiableMacro.arguments,
				   let arguments = LabeledExprListSyntax(macroArguments),
				   let customMockNameIndex = arguments.firstIndex(where: { $0.label?.text == "customMockName" })
				{
					context.diagnose(Diagnostic(
						node: Syntax(instantiableMacro),
						error: FixableInstantiableError.customMockNameWithoutGenerateMock,
						changes: Self.addGenerateMockArgument(to: instantiableMacro, arguments: arguments, customMockNameOffset: arguments.distance(from: arguments.startIndex, to: customMockNameIndex), on: declaration),
					))
				}
				// When generateMock: true and a method named "mock" exists (not custom-named), it must be renamed.
				if instantiableMacro.generateMockValue,
				   customMockNameValue == nil,
				   let firstMock = visitor.mockFunctionSyntax
				{
					context.diagnose(Diagnostic(
						node: Syntax(firstMock),
						error: FixableInstantiableError.mockMethodNeedsCustomName,
						changes: Self.renameMethodToCustomMock(mockSyntax: firstMock, instantiableMacro: instantiableMacro, on: declaration),
					))
				}
				// When customMockName is set and a literal "mock" method also exists, it conflicts with the generated mock.
				if instantiableMacro.generateMockValue,
				   customMockNameValue != nil,
				   let conflictingMock = visitor.conflictingMockFunctionSyntax
				{
					context.diagnose(Diagnostic(
						node: Syntax(conflictingMock),
						error: FixableInstantiableError.mockMethodConflictsWithGeneratedMock,
						changes: [
							.replace(
								oldNode: Syntax(conflictingMock),
								newNode: Syntax("" as DeclSyntax),
							),
						],
					))
				}
				// When customMockName is set but no method with that name is found, emit error.
				if let customMockNameValue,
				   instantiableMacro.generateMockValue,
				   visitor.mockFunctionSyntax == nil
				{
					context.diagnose(Diagnostic(
						node: Syntax(instantiableMacro),
						error: FixableInstantiableError.customMockNameMethodNotFound(customMockNameValue),
						changes: Self.generateCustomMockStub(
							named: customMockNameValue,
							typeName: extendedTypeName,
							dependencies: extensionDependencies,
							isExtension: true,
							on: declaration,
						),
					))
				}
			}
			// Check that non-dependency parameters on mock methods have default values.
			// Validate all overloads, not just the first.
			let dependencyLabels = Set(extensionDependencies.map(\.property.label))
			for mockFunction in allMockFunctions {
				let mockFunctionInitializer = Initializer(mockFunction)
				let nonDependenciesWithoutDefaults = mockFunctionInitializer.arguments
					.filter { !dependencyLabels.contains($0.innerLabel) && !$0.hasDefaultValue }
					.map(\.asProperty)
				if !nonDependenciesWithoutDefaults.isEmpty {
					let nonDependencyLabelsWithoutDefaults = Set(nonDependenciesWithoutDefaults.map(\.label))
					var fixedMock = mockFunction
					fixedMock.signature.parameterClause.parameters = FunctionParameterListSyntax(
						mockFunction.signature.parameterClause.parameters.map { parameter in
							var fixedParameter = parameter
							let parameterLabel = parameter.secondName?.text ?? parameter.firstName.text
							if nonDependencyLabelsWithoutDefaults.contains(parameterLabel),
							   fixedParameter.defaultValue == nil
							{
								fixedParameter.defaultValue = InitializerClauseSyntax(
									equal: .equalToken(leadingTrivia: .space, trailingTrivia: .space),
									value: EditorPlaceholderExprSyntax(placeholder: .identifier("<#default#>")),
								)
							}
							return fixedParameter
						},
					)
					context.diagnose(Diagnostic(
						node: Syntax(mockFunction),
						error: FixableInstantiableError.mockMethodNonDependencyMissingDefaultValue(nonDependenciesWithoutDefaults),
						changes: [
							.replace(
								oldNode: Syntax(mockFunction),
								newNode: Syntax(fixedMock),
							),
						],
					))
				}
			}
			var seenMockReturnTypes = [TypeDescription: FunctionDeclSyntax]()
			for mockFunction in allMockFunctions {
				let mockReturnType = mockFunction.signature.returnClause?.type.typeDescription
				let additionalTypesStrippingGenerics = (visitor.additionalInstantiables ?? []).map(\.strippingGenerics)
				let returnTypeMatchesExtendedType = mockReturnType?.strippingGenerics == extendedTypeStrippingGenerics
					|| additionalTypesStrippingGenerics.contains(where: { $0 == mockReturnType?.strippingGenerics })
				if !returnTypeMatchesExtendedType {
					var fixedMockFunction = mockFunction
					if let existingReturnClause = mockFunction.signature.returnClause {
						fixedMockFunction.signature.returnClause = ReturnClauseSyntax(
							arrow: .arrowToken(
								leadingTrivia: existingReturnClause.arrow.leadingTrivia,
								trailingTrivia: existingReturnClause.arrow.trailingTrivia,
							),
							type: IdentifierTypeSyntax(
								leadingTrivia: existingReturnClause.type.leadingTrivia,
								name: .identifier(extendedTypeName),
								trailingTrivia: existingReturnClause.type.trailingTrivia,
							),
						)
					} else {
						fixedMockFunction.signature.parameterClause.rightParen.trailingTrivia = []
						fixedMockFunction.signature.returnClause = ReturnClauseSyntax(
							arrow: .arrowToken(
								leadingTrivia: .space,
								trailingTrivia: .space,
							),
							type: IdentifierTypeSyntax(
								name: .identifier(extendedTypeName),
								trailingTrivia: .space,
							),
						)
					}
					context.diagnose(Diagnostic(
						node: Syntax(mockFunction),
						error: FixableInstantiableError.mockMethodIncorrectReturnType(typeName: extendedTypeName),
						changes: [
							.replace(
								oldNode: Syntax(mockFunction),
								newNode: Syntax(fixedMockFunction),
							),
						],
					))
				}
				if !mockFunction.modifiers.containsPublicOrOpen {
					var fixedMockFunction = mockFunction
					let firstModifier = mockFunction.modifiers.first
					fixedMockFunction.modifiers.insert(
						DeclModifierSyntax(
							leadingTrivia: firstModifier?.leadingTrivia ?? mockFunction.funcKeyword.leadingTrivia,
							name: .keyword(.public),
							trailingTrivia: .space,
						),
						at: fixedMockFunction.modifiers.startIndex,
					)
					if let firstModifier {
						fixedMockFunction.modifiers[fixedMockFunction.modifiers.startIndex].leadingTrivia = firstModifier.leadingTrivia
						let secondModifierIndex = fixedMockFunction.modifiers.index(after: fixedMockFunction.modifiers.startIndex)
						fixedMockFunction.modifiers[secondModifierIndex].leadingTrivia = []
					}
					context.diagnose(Diagnostic(
						node: Syntax(mockFunction),
						error: FixableInstantiableError.mockMethodNotPublic,
						changes: [
							.replace(
								oldNode: Syntax(mockFunction),
								newNode: Syntax(fixedMockFunction),
							),
						],
					))
				}
				// Duplicate detection: one mock per return type.
				if let mockReturnType {
					if seenMockReturnTypes[mockReturnType] != nil {
						context.diagnose(Diagnostic(
							node: Syntax(mockFunction),
							error: FixableInstantiableError.duplicateMockMethod,
							changes: [
								.replace(
									oldNode: Syntax(mockFunction),
									newNode: Syntax("" as DeclSyntax),
								),
							],
						))
					} else {
						seenMockReturnTypes[mockReturnType] = mockFunction
					}
				}
				// Argument validation: mock must have parameters matching the instantiate() method's dependencies.
				if let mockReturnType,
				   let matchingInstantiable = visitor.instantiables.first(where: { $0.concreteInstantiable == mockReturnType }),
				   !matchingInstantiable.dependencies.isEmpty
				{
					let mockInitializer = Initializer(mockFunction)
					do {
						try mockInitializer.validate(fulfilling: matchingInstantiable.dependencies)
					} catch {
						if let fixableError = error.asFixableError,
						   case let .missingArguments(missingArguments) = fixableError.asErrorToFix
						{
							var fixedSyntax = mockFunction
							fixedSyntax.signature.parameterClause = Self.buildFixedParameterClause(
								from: mockFunction.signature.parameterClause,
								requiredProperties: matchingInstantiable.dependencies.map(\.property),
							)
							context.diagnose(Diagnostic(
								node: Syntax(mockFunction),
								error: FixableInstantiableError.mockMethodMissingArguments(missingArguments),
								changes: [
									.replace(
										oldNode: Syntax(mockFunction),
										newNode: Syntax(fixedSyntax),
									),
								],
							))
						}
					}
				}
			}

			if visitor.isRoot, let instantiableType = visitor.instantiableType {
				let rootDependencies = visitor.instantiables
					.first(where: { $0.concreteInstantiable == instantiableType })?
					.dependencies ?? []
				guard rootDependencies.isEmpty else {
					throw InstantiableError.cannotBeRoot(
						instantiableType,
						violatingDependencies: rootDependencies,
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
										presence: .present,
									),
									trailingTrivia: .space,
								),
								DeclModifierSyntax(
									name: TokenSyntax(
										TokenKind.keyword(.static),
										presence: .present,
									),
									trailingTrivia: .space,
								),
							),
							name: TokenSyntax(
								TokenKind.identifier(InstantiableVisitor.instantiateMethodName),
								leadingTrivia: .space,
								presence: .present,
							),
							signature: FunctionSignatureSyntax(
								parameterClause: FunctionParameterClauseSyntax(
									parameters: FunctionParameterListSyntax([]),
								),
								returnClause: ReturnClauseSyntax(
									arrow: .arrowToken(
										leadingTrivia: .space,
										trailingTrivia: .space,
									),
									type: IdentifierTypeSyntax(
										name: .identifier(extendedTypeName),
									),
								),
							),
							body: CodeBlockSyntax(
								leadingTrivia: .newline,
								statements: CodeBlockItemListSyntax([]),
								trailingTrivia: .newline,
							),
						),
						trailingTrivia: .newline,
					),
					at: membersWithInitializer.startIndex,
				)
				context.diagnose(Diagnostic(
					node: Syntax(extensionDeclaration.memberBlock.members),
					error: FixableInstantiableError.missingRequiredInstantiateMethod(
						typeName: extendedTypeName,
					),
					changes: [
						.replace(
							oldNode: Syntax(declaration.memberBlock.members),
							newNode: Syntax(membersWithInitializer),
						),
					],
				))
			}
			return []
		} else {
			throw InstantiableError.decoratingIncompatibleType
		}
	}

	private static func generateForwardedProperties(
		from forwardedProperties: [Property],
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
									presence: .present,
								),
								trailingTrivia: .space,
							),
						),
						name: .identifier("ForwardedProperties"),
						initializer: TypeInitializerClauseSyntax(
							value: IdentifierTypeSyntax(
								name: .identifier(forwardedProperty.typeDescription.asSource),
							),
						),
					),
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
									presence: .present,
								),
								trailingTrivia: .space,
							),
						),
						name: .identifier("ForwardedProperties"),
						initializer: TypeInitializerClauseSyntax(value: forwardedProperties.asTuple),
					),
				),
			]
		}
	}

	// MARK: - Parameter Clause Fix-It

	/// Builds a fixed parameter clause that includes all required properties in order,
	/// preserving existing parameters where possible and appending any remaining
	/// non-required parameters at the end.
	private static func buildFixedParameterClause(
		from original: FunctionParameterClauseSyntax,
		requiredProperties: [Property],
	) -> FunctionParameterClauseSyntax {
		var result = original
		let existingArgumentCount = original.parameters.count
		var existingParameters = original.parameters.reduce(into: [Property: FunctionParameterSyntax]()) { partialResult, next in
			partialResult[Initializer.Argument(next).asProperty] = next
		}
		result.parameters = []
		for property in requiredProperties {
			if let existingParameter = existingParameters.removeValue(forKey: property) {
				result.parameters.append(existingParameter)
			} else {
				result.parameters.append(property.asFunctionParamterSyntax)
			}
		}
		// Append remaining non-required parameters (e.g., extra parameters with defaults).
		for (_, parameter) in existingParameters {
			result.parameters.append(parameter)
		}
		// Fix up trailing commas.
		for index in result.parameters.indices {
			if index == result.parameters.index(before: result.parameters.endIndex) {
				result.parameters[index].trailingComma = nil
			} else {
				result.parameters[index].trailingComma = result.parameters[index].trailingComma ?? .commaToken(trailingTrivia: .space)
			}
		}
		// Fix up trivia for multi-parameter layout.
		if result.parameters.count > 1 {
			for index in result.parameters.indices {
				if index == result.parameters.startIndex {
					result.parameters[index].leadingTrivia = existingArgumentCount > 1
						? original.parameters.first?.leadingTrivia ?? .newline
						: .newline
				}
				if index == result.parameters.index(before: result.parameters.endIndex) {
					result.parameters[index].trailingTrivia = existingArgumentCount > 1
						? original.parameters.last?.trailingTrivia ?? .newline
						: .newline
				}
			}
		}
		return result
	}

	/// Builds fix-it changes that add `generateMock: true` to an existing `@Instantiable` attribute.
	private static func addGenerateMockArgument(
		to attribute: AttributeSyntax,
		arguments: LabeledExprListSyntax,
		customMockNameOffset: Int,
		on declaration: some SyntaxProtocol,
	) -> [FixIt.Change] {
		var fixedAttribute = attribute
		let generateMockArgument = LabeledExprSyntax(
			label: .identifier("generateMock"),
			colon: .colonToken(trailingTrivia: .space),
			expression: BooleanLiteralExprSyntax(booleanLiteral: true),
			trailingComma: .commaToken(trailingTrivia: .space),
		)
		// Insert generateMock: true before customMockName to preserve parameter order.
		var newArguments = Array(arguments)
		newArguments.insert(generateMockArgument, at: customMockNameOffset)
		fixedAttribute.arguments = .argumentList(LabeledExprListSyntax(newArguments))
		let rewriter = AttributeRewriter(oldID: attribute.id, replacement: fixedAttribute)
		let fixedDeclaration = rewriter.rewrite(Syntax(declaration))
		return [.replace(oldNode: Syntax(declaration), newNode: fixedDeclaration)]
	}

	/// Builds fix-it changes that rename a `mock()` method to `customMock()` and add `customMockName: "customMock"` to the attribute.
	private static func renameMethodToCustomMock(
		mockSyntax: FunctionDeclSyntax,
		instantiableMacro: AttributeSyntax,
		on declaration: some SyntaxProtocol,
	) -> [FixIt.Change] {
		// Rename the method from "mock" to "customMock".
		var renamedMock = mockSyntax
		renamedMock.name = .identifier("customMock")

		// Add customMockName: "customMock" to the attribute.
		var fixedAttribute = instantiableMacro
		let customMockNameArgument = LabeledExprSyntax(
			label: .identifier("customMockName"),
			colon: .colonToken(trailingTrivia: .space),
			expression: StringLiteralExprSyntax(content: "customMock"),
		)
		let labeledExpressionList = LabeledExprListSyntax(instantiableMacro.arguments!)!
		var newArguments = Array(labeledExpressionList)
		if var lastArgument = newArguments.last {
			lastArgument.trailingComma = .commaToken(trailingTrivia: .space)
			newArguments[newArguments.count - 1] = lastArgument
		}
		newArguments.append(customMockNameArgument)
		fixedAttribute.arguments = .argumentList(LabeledExprListSyntax(newArguments))

		// Apply both changes: rename method and update attribute.
		let rewriter = AttributeRewriter(oldID: instantiableMacro.id, replacement: fixedAttribute)
		let fixedDeclaration = rewriter.rewrite(Syntax(declaration))
		return [
			.replace(oldNode: Syntax(mockSyntax), newNode: Syntax(renamedMock)),
			.replace(oldNode: Syntax(declaration), newNode: fixedDeclaration),
		]
	}

	/// Builds fix-it changes that generate a stub custom mock method below the initializer.
	private static func generateCustomMockStub(
		named name: String,
		typeName: String,
		dependencies: [Dependency],
		isExtension: Bool = false,
		on declaration: some DeclGroupSyntax,
	) -> [FixIt.Change] {
		let parameters = dependencies.map { dependency in
			FunctionParameterSyntax(
				firstName: .identifier(dependency.property.label),
				colon: .colonToken(trailingTrivia: .space),
				type: IdentifierTypeSyntax(name: .identifier(dependency.property.typeDescription.asSource)),
			)
		}
		let parameterList = FunctionParameterListSyntax(
			parameters.enumerated().map { index, parameter in
				var parameter = parameter
				if index < parameters.count - 1 {
					parameter.trailingComma = .commaToken(trailingTrivia: .space)
				}
				return parameter
			},
		)

		// Build a compilable body: `TypeName(dep1: dep1, dep2: dep2)` for concrete types,
		// `TypeName.instantiate(dep1: dep1, dep2: dep2)` for extension types.
		let argumentList = dependencies.enumerated().map { index, dependency in
			let trailingComma = index < dependencies.count - 1 ? ", " : ""
			return "\(dependency.property.label): \(dependency.property.label)\(trailingComma)"
		}.joined()
		let construction = if isExtension {
			"\(typeName).\(InstantiableVisitor.instantiateMethodName)(\(argumentList))"
		} else {
			"\(typeName)(\(argumentList))"
		}

		let stubMethod = FunctionDeclSyntax(
			modifiers: DeclModifierListSyntax(
				arrayLiteral: DeclModifierSyntax(
					name: TokenSyntax(
						TokenKind.keyword(.public),
						presence: .present,
					),
					trailingTrivia: .space,
				),
				DeclModifierSyntax(
					name: TokenSyntax(
						TokenKind.keyword(.static),
						presence: .present,
					),
					trailingTrivia: .space,
				),
			),
			name: TokenSyntax(
				TokenKind.identifier(name),
				leadingTrivia: .space,
				presence: .present,
			),
			signature: FunctionSignatureSyntax(
				parameterClause: FunctionParameterClauseSyntax(
					parameters: parameterList,
				),
				returnClause: ReturnClauseSyntax(
					arrow: .arrowToken(
						leadingTrivia: .space,
						trailingTrivia: .space,
					),
					type: IdentifierTypeSyntax(
						name: .identifier(typeName),
					),
				),
			),
			body: CodeBlockSyntax(
				leadingTrivia: .space,
				statements: CodeBlockItemListSyntax([
					CodeBlockItemSyntax(
						item: .expr(ExprSyntax(stringLiteral: construction)),
					),
				]),
				trailingTrivia: .newline,
			),
		)

		var membersWithStub = declaration.memberBlock.members
		membersWithStub.append(
			MemberBlockItemSyntax(
				leadingTrivia: .newline,
				decl: stubMethod,
				trailingTrivia: .newline,
			),
		)
		return [
			.replace(
				oldNode: Syntax(declaration.memberBlock.members),
				newNode: Syntax(membersWithStub),
			),
		]
	}

	// MARK: - InstantiableError

	private enum InstantiableError: Error, CustomStringConvertible {
		case decoratingIncompatibleType
		case fulfillingAdditionalTypesContainsOptional
		case fulfillingAdditionalTypesArgumentInvalid
		case mockAttributesArgumentInvalid
		case generateMockArgumentInvalid
		case customMockNameArgumentInvalid
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
			case .mockAttributesArgumentInvalid:
				"The argument `mockAttributes` must be a string literal"
			case .generateMockArgumentInvalid:
				"The argument `generateMock` must be a Bool literal (`true` or `false`)"
			case .customMockNameArgumentInvalid:
				"The argument `customMockName` must be a string literal or `nil`"
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
				parentType: .simple(name: "SafeDI"),
			)
			|| self == .attributed(
				.simple(name: "Instantiable"),
				specifiers: [],
				attributes: ["retroactive"],
			)
			|| self == .nested(
				name: "Instantiable",
				parentType: .attributed(
					.simple(name: "SafeDI"),
					specifiers: [],
					attributes: ["retroactive"],
				),
			)
	}
}

// MARK: Initializer

extension Initializer {
	fileprivate enum FixableError: Comparable, Hashable {
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

// MARK: - AttributeRewriter

/// Replaces a single attribute in a syntax tree by matching its node ID.
private final class AttributeRewriter: SyntaxRewriter {
	let oldID: SyntaxIdentifier
	let replacement: AttributeSyntax
	init(oldID: SyntaxIdentifier, replacement: AttributeSyntax) {
		self.oldID = oldID
		self.replacement = replacement
	}

	override func visit(_ node: AttributeSyntax) -> AttributeSyntax {
		if node.id == oldID {
			return replacement
		}
		return node
	}
}
