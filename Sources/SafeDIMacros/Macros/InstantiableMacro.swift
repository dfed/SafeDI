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
import SwiftParser
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
				if let optionalElement = arrayExpression
					.elements
					.first(where: \.expression.typeDescription.isOptional)
				{
					throw InstantiableError.fulfillingAdditionalTypesContainsOptional(optionalElement.expression.trimmedDescription)
				}
			} else {
				throw InstantiableError.fulfillingAdditionalTypesArgumentInvalid
			}
		}

		if let generatedInitializerAttributesArgument = declaration
			.attributes
			.instantiableMacro?
			.generatedInitializerAttributes, StringLiteralExprSyntax(generatedInitializerAttributesArgument) == nil
		{
			throw InstantiableError.generatedInitializerAttributesArgumentInvalid
		}

		if let mockAttributesArgument = declaration
			.attributes
			.instantiableMacro?
			.mockAttributes, StringLiteralExprSyntax(mockAttributesArgument) == nil
		{
			throw InstantiableError.mockAttributesArgumentInvalid
		}

		if let generatedAttributesArgument = declaration
			.attributes
			.instantiableMacro?
			.generatedAttributes, StringLiteralExprSyntax(generatedAttributesArgument) == nil
		{
			throw InstantiableError.generatedAttributesArgumentInvalid
		}

		if let generateMockArgument = declaration
			.attributes
			.instantiableMacro?
			.generateMock, AttributeSyntax.mockGeneration(spelledAs: generateMockArgument) == nil
		{
			throw InstantiableError.generateMockArgumentInvalid
		}

		if let mockOnlyArgument = declaration
			.attributes
			.instantiableMacro?
			.mockOnly, BooleanLiteralExprSyntax(mockOnlyArgument) == nil
		{
			throw InstantiableError.mockOnlyArgumentInvalid
		}

		if let generateDependencyTreeArgument = declaration
			.attributes
			.instantiableMacro?
			.generateDependencyTree, BooleanLiteralExprSyntax(generateDependencyTreeArgument) == nil
		{
			throw InstantiableError.generateDependencyTreeArgumentInvalid
		}

		if let customMockNameArgument = declaration
			.attributes
			.instantiableMacro?
			.customMockName, NilLiteralExprSyntax(customMockNameArgument) == nil,
			StringLiteralExprSyntax(customMockNameArgument) == nil
		{
			throw InstantiableError.customMockNameArgumentInvalid
		}

		if let concreteDeclaration: ConcreteDeclSyntaxProtocol
			= ActorDeclSyntax(declaration)
			?? ClassDeclSyntax(declaration)
			?? StructDeclSyntax(declaration)
		{
			let isMockOnly = declaration.attributes.instantiableMacro?.mockOnlyValue ?? false

			lazy var extendsInstantiable = concreteDeclaration.inheritanceClause?.inheritedTypes.contains(where: \.type.typeDescription.isInstantiable) ?? false
			let mustExtendInstantiable = if isMockOnly {
				false
			} else if let conformsElsewhereArgument = declaration.attributes.instantiableMacro?.conformsElsewhere,
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
			Self.diagnoseRenamesOfRenamesAndOfThemselves(among: declaration.memberBlock.members, context: context)

			let memberDeclarations = Self.declarations(in: declaration.memberBlock.members)
			Self.diagnoseNestedTypesSpelledThroughSelf(
				in: memberDeclarations
					.compactMap { VariableDeclSyntax($0) }
					.flatMap { variable -> [DependencyTypeSyntax] in
						guard let dependencyAttribute = variable.attributes.dependencySources.first?.attribute else {
							return []
						}
						return variable.bindings.compactMap { binding in
							IdentifierPatternSyntax(binding.pattern).flatMap { pattern in
								binding.typeAnnotation.map {
									DependencyTypeSyntax(name: pattern.identifier, type: $0.type, aliasedType: dependencyAttribute.ofType)
								}
							}
						}
					},
				fulfilledByParametersOf: memberDeclarations.compactMap { InitializerDeclSyntax($0)?.signature }
					+ Self.mockFunctionSignatures(foundBy: visitor),
				declaredAmong: memberDeclarations,
				enclosingType: Self.qualifiedType(named: concreteDeclaration.name.text, in: context),
				context: context,
			)

			if isMockOnly,
			   let instantiableMacro = declaration.attributes.instantiableMacro,
			   instantiableMacro.generateMockValue
			{
				context.diagnose(Diagnostic(
					node: Syntax(instantiableMacro),
					error: FixableInstantiableError.mockOnlyWithGenerateMock(spelling: Self.spelling(ofGenerateMockArgumentOf: instantiableMacro)),
					changes: Self.removeArgument(labeled: "generateMock", from: instantiableMacro, on: declaration),
				))
			}
			if !isMockOnly,
			   let instantiableMacro = declaration.attributes.instantiableMacro
			{
				Self.validatePublicMockGeneration(
					of: concreteDeclaration,
					genericParameterClause: StructDeclSyntax(declaration)?.genericParameterClause
						?? ClassDeclSyntax(declaration)?.genericParameterClause
						?? ActorDeclSyntax(declaration)?.genericParameterClause,
					instantiableMacro: instantiableMacro,
					context: context,
				)
			}
			if isMockOnly, visitor.isRoot,
			   let instantiableMacro = declaration.attributes.instantiableMacro
			{
				context.diagnose(Diagnostic(
					node: Syntax(instantiableMacro),
					error: FixableInstantiableError.mockOnlyWithIsRoot,
					changes: Self.removeArgument(labeled: "isRoot", from: instantiableMacro, on: declaration),
				))
			}
			if isMockOnly,
			   let instantiableMacro = declaration.attributes.instantiableMacro,
			   instantiableMacro.mockAttributes != nil
			{
				context.diagnose(Diagnostic(
					node: Syntax(instantiableMacro),
					error: FixableInstantiableError.mockAttributesOnMockOnly,
					changes: Self.removeArgument(labeled: "mockAttributes", from: instantiableMacro, on: declaration),
				))
			}
			if visitor.generatesDependencyTree, visitor.isRoot,
			   let instantiableMacro = declaration.attributes.instantiableMacro
			{
				context.diagnose(Diagnostic(
					node: Syntax(instantiableMacro),
					error: FixableInstantiableError.generateDependencyTreeWithIsRoot,
					changes: Self.removeArgument(labeled: "generateDependencyTree", from: instantiableMacro, on: declaration),
				))
			}
			if visitor.generatesDependencyTree, isMockOnly,
			   let instantiableMacro = declaration.attributes.instantiableMacro
			{
				context.diagnose(Diagnostic(
					node: Syntax(instantiableMacro),
					error: FixableInstantiableError.generateDependencyTreeWithMockOnly,
					changes: Self.removeArgument(labeled: "generateDependencyTree", from: instantiableMacro, on: declaration),
				))
			}
			if isMockOnly, visitor.mockFunctionSyntax == nil {
				let expectedMethodName = visitor.customMockName ?? InstantiableVisitor.mockMethodName
				let accessModifier = Self.accessModifierOfDeclarationAdded(to: concreteDeclaration, takingParametersOf: visitor.dependencies, context: context)
				context.diagnose(Diagnostic(
					node: Syntax(node),
					error: FixableInstantiableError.mockOnlyMissingMockMethod(
						typeName: concreteDeclaration.name.text,
						methodName: expectedMethodName,
						accessModifier: accessModifier,
					),
					changes: Self.generateCustomMockStub(
						named: expectedMethodName,
						typeName: concreteDeclaration.name.text,
						dependencies: visitor.dependencies,
						accessModifier: accessModifier,
						on: declaration,
					),
				))
			}

			if visitor.isRoot, let instantiableType = visitor.instantiableType {
				let inheritedDependencies = visitor.dependencies.filter {
					switch $0.source {
					case let .aliased(fulfillingProperty, _, _):
						// Aliased properties must not be inherited from elsewhere. A property this type declares
						// fulfills one (a received property is reported itself), and so does the instance of a
						// lazily instantiated property it instantiates or renames, as in `Scope.createdProperties`.
						!visitor.dependencies.contains { $0.receivableProperties.contains(fulfillingProperty) }
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

			// Diagnose unmockable init shapes (unlabeled default before an
			// unlabeled required parameter) on every candidate initializer.
			// Runs regardless of `generateMock`/`mockOnly` because the shape
			// is awkward for any future mock use and the diagnostic is local.
			for (initializer, initializerSyntax) in zip(visitor.initializers, visitor.initializerSyntaxes) {
				Self.validateUnlabeledDefaultShape(
					functionSyntax: initializerSyntax.signature,
					arguments: initializer.arguments,
					dependencies: visitor.dependencies,
					diagnosticNode: Syntax(initializerSyntax),
					context: context,
				)
			}
			// Only check init defaults on the initializer SafeDI actually uses
			// for mock construction — `InstantiableVisitor` selects the first
			// initializer that fulfills the dependencies (see
			// `InstantiableVisitor:377`), and `generateMockRootCode` reads that
			// same initializer. Convenience or secondary inits with `Self.*`
			// defaults never reach the override surface, so diagnosing them
			// would be a false positive. Also skipped when a custom mock
			// exists — then SafeDI prefers `mockInitializer` over any init.
			if visitor.mockInitializer == nil,
			   let (_, selectedInitializerSyntax) = zip(visitor.initializers, visitor.initializerSyntaxes).first(where: { initializer, _ in
			   	initializer.isValid(forFulfilling: visitor.dependencies)
			   })
			{
				Self.validateDefaultExpressions(
					functionSyntax: selectedInitializerSyntax.signature,
					dependencies: visitor.dependencies,
					typeName: concreteDeclaration.name.text,
					context: context,
				)
				Self.validateReservedParameterLabels(
					functionSyntax: selectedInitializerSyntax.signature,
					dependencies: visitor.dependencies,
					context: context,
				)
			}
			if let mockInitializer = visitor.mockInitializer,
			   let mockSyntax = visitor.mockFunctionSyntax
			{
				Self.validateUnlabeledDefaultShape(
					functionSyntax: mockSyntax.signature,
					arguments: mockInitializer.arguments,
					dependencies: visitor.dependencies,
					diagnosticNode: Syntax(mockSyntax),
					context: context,
				)
				Self.validateDefaultExpressions(
					functionSyntax: mockSyntax.signature,
					dependencies: visitor.dependencies,
					typeName: concreteDeclaration.name.text,
					context: context,
				)
				Self.validateReservedParameterLabels(
					functionSyntax: mockSyntax.signature,
					dependencies: visitor.dependencies,
					context: context,
				)
			}

			let hasMemberwiseInitializerForInjectableProperties = isMockOnly || visitor.canonicalConstructionInitializer != nil
			guard hasMemberwiseInitializerForInjectableProperties else {
				// SafeDI matches parameters to properties by name, so names encoded differently also leave the initializer
				// unmatched. The error at those names says why, and the initializer's error would only repeat it.
				guard !visitor.hasNamesEncodedDifferently else { return [] }
				func associatedError(for initializer: Initializer, declaredBy syntax: InitializerDeclSyntax) -> (initializer: Initializer, syntax: InitializerDeclSyntax, error: Initializer.FixableError)? {
					do {
						try initializer.validate(fulfilling: visitor.dependencies)
					} catch {
						if let fixableError = error.asFixableError {
							return (initializer: initializer, syntax: syntax, error: fixableError)
						}
					}
					return nil
				}
				// Of the initializers that need the smallest change, the first declared is fixed.
				let initializerToFix: (initializer: Initializer, syntax: InitializerDeclSyntax, error: Initializer.FixableError)? = zip(visitor.initializers, visitor.initializerSyntaxes).compactMap {
					associatedError(for: $0, declaredBy: $1)
				}.enumerated().min { lhs, rhs in
					// Two different errors can need equally small changes, so neither precedes the other.
					if lhs.element.error < rhs.element.error {
						true
					} else if rhs.element.error < lhs.element.error {
						false
					} else {
						lhs.offset < rhs.offset
					}
				}?.element

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

						// Inserted in source order, each parameter lands among those inserted before it.
						for priorIndex in syntaxToFix.signature.parameterClause.parameters.indices {
							let existingParameter = syntaxToFix.signature.parameterClause.parameters[priorIndex]
							if existingParameters[Initializer.Argument(existingParameter).asProperty] == existingParameter {
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
								   let property = propertyLabelToPropertyMap[String(splitStatement[1]).spelledAsIdentifier]
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

					case let .inaccessibleInitializer(accessLevel):
						// Only a `private` or `fileprivate` initializer is inaccessible to generated code.
						context.diagnose(Diagnostic(
							node: Syntax(syntaxToFix),
							error: FixableInstantiableError.missingRequiredInitializer(.isPrivateOrFilePrivate(accessLevel)),
							changes: [
								.replace(
									oldNode: Syntax(syntaxToFix),
									newNode: Syntax(syntaxToFix.removingModifiers(setting: accessLevel, keyword: \.initKeyword)),
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
								accessLevel: Self.accessModifierOfDeclarationAdded(to: concreteDeclaration, takingParametersOf: visitor.dependencies, context: context),
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
					// An initializer that is `async` or `throws` would otherwise go unexplained.
					let effectfulInitializerNotes = zip(visitor.initializers, visitor.initializerSyntaxes)
						.filter { initializer, _ in initializer.isAsync || initializer.doesThrow }
						.map { _, syntax in Note(node: Syntax(syntax), message: EffectfulInitializerNote()) }
					context.diagnose(Diagnostic(
						node: Syntax(declaration.memberBlock),
						error: FixableInstantiableError.missingRequiredInitializer(errorType),
						notes: effectfulInitializerNotes,
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

			// Validate customMockName: requires generateMock: true or mockOnly: true.
			if let instantiableMacro = declaration.attributes.instantiableMacro {
				let customMockNameValue = instantiableMacro.customMockNameValue
				if customMockNameValue != nil,
				   !instantiableMacro.generateMockValue,
				   !isMockOnly,
				   let macroArguments = instantiableMacro.arguments,
				   let arguments = LabeledExprListSyntax(macroArguments),
				   let customMockNameIndex = arguments.firstIndex(where: { $0.label?.text == "customMockName" })
				{
					context.diagnose(Diagnostic(
						node: Syntax(instantiableMacro),
						error: FixableInstantiableError.customMockNameWithoutMockGeneration,
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
				   let customMockNameValue,
				   let conflictingMock = visitor.conflictingMockFunctionSyntax
				{
					context.diagnose(Diagnostic(
						node: Syntax(conflictingMock),
						error: FixableInstantiableError.mockMethodConflictsWithGeneratedMock(customMockName: customMockNameValue),
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
					let accessModifier = Self.accessModifierOfDeclarationAdded(to: concreteDeclaration, takingParametersOf: visitor.dependencies, context: context)
					context.diagnose(Diagnostic(
						node: Syntax(instantiableMacro),
						error: FixableInstantiableError.customMockNameMethodNotFound(name: customMockNameValue, accessModifier: accessModifier),
						changes: Self.generateCustomMockStub(
							named: customMockNameValue,
							typeName: concreteDeclaration.name.text,
							dependencies: visitor.dependencies,
							accessModifier: accessModifier,
							on: declaration,
						),
					))
				}
			}

			// Validate mock method if one exists: must not be private or fileprivate, must return Self or the type name, and must have parameters for all dependencies.
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
							let parameterLabel = (parameter.secondName ?? parameter.firstName).spelledAsParameterName
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
				let isSelfReturnType = mockReturnType == .simple(name: "Self", generics: [])
				// Concrete type mocks must return Self or the type name.
				// Additional types are only allowed for extension-based mocks.
				let returnTypeMatchesTypeName = isSelfReturnType
					|| mockReturnType?.strippingGenerics == instantiableTypeStrippingGenerics
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
				// Any other access can suit the generated mocks that call the method; SafeDITool checks those, which it
				// generates.
				if let (fixedMockSyntax, accessLevel) = mockSyntax.removingPrivateOrFilePrivateModifier(keyword: \.funcKeyword) {
					context.diagnose(Diagnostic(
						node: Syntax(mockSyntax),
						error: FixableInstantiableError.privateOrFilePrivateMockMethod(accessLevel),
						changes: [
							.replace(
								oldNode: Syntax(mockSyntax),
								newNode: Syntax(fixedMockSyntax),
							),
						],
					))
				}
				if mockInitializer.isAsync || mockInitializer.doesThrow {
					context.diagnose(Self.mockMethodHasEffectSpecifiersDiagnostic(for: mockSyntax))
				}
				if !visitor.dependencies.isEmpty, !visitor.hasNamesEncodedDifferently {
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
								error: FixableInstantiableError.mockMethodMissingArguments(methodName: mockSyntax.name.text, missingArguments),
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
			let isMockOnly = declaration.attributes.instantiableMacro?.mockOnlyValue ?? false

			lazy var extendsInstantiable = extensionDeclaration.inheritanceClause?.inheritedTypes.contains(where: \.type.typeDescription.isInstantiable) ?? false
			let mustExtendInstantiable = if isMockOnly {
				false
			} else if let conformsElsewhereArgument = declaration.attributes.instantiableMacro?.conformsElsewhere,
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

			// Each parameter of `instantiate(…)` without a default value is a dependency, as `InstantiableVisitor` finds.
			Self.diagnoseNestedTypesSpelledThroughSelf(
				in: visitor.instantiateFunctions.flatMap { instantiateFunction in
					instantiateFunction.syntax.signature.parameterClause.parameters
						.filter { $0.defaultValue == nil }
						.map { DependencyTypeSyntax(name: $0.secondName ?? $0.firstName, type: $0.type, aliasedType: nil) }
				},
				fulfilledByParametersOf: Self.mockFunctionSignatures(foundBy: visitor),
				declaredAmong: Self.declarations(in: declaration.memberBlock.members),
				// An extension is declared at file scope, so it spells the type it extends with every enclosing type.
				enclosingType: extensionDeclaration.extendedType.typeDescription,
				context: context,
			)

			// An extension cannot prove the type it extends is `public`.
			if !isMockOnly,
			   let instantiableMacro = declaration.attributes.instantiableMacro,
			   instantiableMacro.mockGenerationValue == .public,
			   let generateMockArgument = instantiableMacro.generateMock
			{
				context.diagnose(Diagnostic(
					node: Syntax(generateMockArgument),
					error: FixableInstantiableError.publicMockOnExtension,
					changes: [Self.replacing(generateMockArgument, with: ".internal")],
				))
			}
			// Validate mockOnly on extensions.
			if isMockOnly,
			   let instantiableMacro = declaration.attributes.instantiableMacro,
			   instantiableMacro.generateMockValue
			{
				context.diagnose(Diagnostic(
					node: Syntax(instantiableMacro),
					error: FixableInstantiableError.mockOnlyWithGenerateMock(spelling: Self.spelling(ofGenerateMockArgumentOf: instantiableMacro)),
					changes: Self.removeArgument(labeled: "generateMock", from: instantiableMacro, on: declaration),
				))
			}
			if isMockOnly, visitor.isRoot,
			   let instantiableMacro = declaration.attributes.instantiableMacro
			{
				context.diagnose(Diagnostic(
					node: Syntax(instantiableMacro),
					error: FixableInstantiableError.mockOnlyWithIsRoot,
					changes: Self.removeArgument(labeled: "isRoot", from: instantiableMacro, on: declaration),
				))
			}
			if isMockOnly,
			   let instantiableMacro = declaration.attributes.instantiableMacro,
			   instantiableMacro.mockAttributes != nil
			{
				context.diagnose(Diagnostic(
					node: Syntax(instantiableMacro),
					error: FixableInstantiableError.mockAttributesOnMockOnly,
					changes: Self.removeArgument(labeled: "mockAttributes", from: instantiableMacro, on: declaration),
				))
			}
			if isMockOnly, visitor.mockFunctionSyntax == nil {
				let expectedMethodName = visitor.customMockName ?? InstantiableVisitor.mockMethodName
				let accessModifier = Self.accessModifierOfDeclarationAdded(to: extensionDeclaration, besideInstantiateMethods: visitor.instantiateFunctions, takingParametersOf: [])
				context.diagnose(Diagnostic(
					node: Syntax(node),
					error: FixableInstantiableError.mockOnlyMissingMockMethod(
						typeName: extensionDeclaration.extendedType.typeDescription.asSource,
						methodName: expectedMethodName,
						accessModifier: accessModifier,
					),
					changes: Self.generateCustomMockStub(
						named: expectedMethodName,
						typeName: extensionDeclaration.extendedType.typeDescription.asSource,
						dependencies: [],
						accessModifier: accessModifier,
						isExtension: true,
						on: declaration,
					),
				))
			}

			// Validate mock() methods on extensions: must not be private or fileprivate, must return the extended type or one of its `fulfillingAdditionalTypes`, and must be unique per return type.
			let extendedTypeDescription = extensionDeclaration.extendedType.typeDescription
			let extendedTypeName = extendedTypeDescription.asSource
			let extendedTypeStrippingGenerics = extendedTypeDescription.strippingGenerics
			var allMockFunctions = [FunctionDeclSyntax]()
			if let firstMock = visitor.mockFunctionSyntax {
				allMockFunctions.append(firstMock)
			}
			allMockFunctions.append(contentsOf: visitor.duplicateMockFunctionSyntaxes)
			let extensionDependencies = visitor.instantiables.flatMap(\.dependencies)
			// Validate customMockName: requires generateMock: true or mockOnly: true.
			if let instantiableMacro = declaration.attributes.instantiableMacro {
				let customMockNameValue = instantiableMacro.customMockNameValue
				if customMockNameValue != nil,
				   !instantiableMacro.generateMockValue,
				   !isMockOnly,
				   let macroArguments = instantiableMacro.arguments,
				   let arguments = LabeledExprListSyntax(macroArguments),
				   let customMockNameIndex = arguments.firstIndex(where: { $0.label?.text == "customMockName" })
				{
					context.diagnose(Diagnostic(
						node: Syntax(instantiableMacro),
						error: FixableInstantiableError.customMockNameWithoutMockGeneration,
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
				   let customMockNameValue,
				   let conflictingMock = visitor.conflictingMockFunctionSyntax
				{
					context.diagnose(Diagnostic(
						node: Syntax(conflictingMock),
						error: FixableInstantiableError.mockMethodConflictsWithGeneratedMock(customMockName: customMockNameValue),
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
					let accessModifier = Self.accessModifierOfDeclarationAdded(to: extensionDeclaration, besideInstantiateMethods: visitor.instantiateFunctions, takingParametersOf: extensionDependencies)
					context.diagnose(Diagnostic(
						node: Syntax(instantiableMacro),
						error: FixableInstantiableError.customMockNameMethodNotFound(name: customMockNameValue, accessModifier: accessModifier),
						changes: Self.generateCustomMockStub(
							named: customMockNameValue,
							typeName: extendedTypeName,
							dependencies: extensionDependencies,
							accessModifier: accessModifier,
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
				// For per-overload default-expression checks, resolve this mock's
				// dependencies from the matching `instantiate()` return type — not
				// the union across all overloads. Otherwise a label that is a
				// non-dependency default for *this* overload but a dependency for
				// another would incorrectly skip the callee-scope check.
				//
				// `Self` return types are mapped to the extended type so the
				// match succeeds: the visitor records instantiables by the actual
				// extended type, not literal `Self`. Falls back to the union
				// only when the return type is unknown (shouldn't happen for
				// well-formed input).
				let rawMockReturnType = mockFunction.signature.returnClause?.type.typeDescription
				let mockReturnType: TypeDescription? = if rawMockReturnType == .simple(name: "Self", generics: []) {
					extendedTypeDescription
				} else {
					rawMockReturnType
				}
				let dependenciesForMock: [Dependency] = if let mockReturnType,
				                                           let matchingInstantiable = visitor.instantiables.first(where: { $0.concreteInstantiable == mockReturnType })
				{
					matchingInstantiable.dependencies
				} else {
					extensionDependencies
				}
				Self.validateUnlabeledDefaultShape(
					functionSyntax: mockFunction.signature,
					arguments: mockFunctionInitializer.arguments,
					dependencies: extensionDependencies,
					diagnosticNode: Syntax(mockFunction),
					context: context,
				)
				Self.validateDefaultExpressions(
					functionSyntax: mockFunction.signature,
					dependencies: dependenciesForMock,
					typeName: extendedTypeName,
					context: context,
				)
				Self.validateReservedParameterLabels(
					functionSyntax: mockFunction.signature,
					dependencies: dependenciesForMock,
					context: context,
				)
				let nonDependenciesWithoutDefaults = mockFunctionInitializer.arguments
					.filter { !dependencyLabels.contains($0.innerLabel) && !$0.hasDefaultValue }
					.map(\.asProperty)
				if !nonDependenciesWithoutDefaults.isEmpty {
					let nonDependencyLabelsWithoutDefaults = Set(nonDependenciesWithoutDefaults.map(\.label))
					var fixedMock = mockFunction
					fixedMock.signature.parameterClause.parameters = FunctionParameterListSyntax(
						mockFunction.signature.parameterClause.parameters.map { parameter in
							var fixedParameter = parameter
							let parameterLabel = (parameter.secondName ?? parameter.firstName).spelledAsParameterName
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
						error: FixableInstantiableError.extensionMockMethodIncorrectReturnType(typeName: extendedTypeName),
						changes: [
							.replace(
								oldNode: Syntax(mockFunction),
								newNode: Syntax(fixedMockFunction),
							),
						],
					))
				}
				if let (fixedMockFunction, accessLevel) = mockFunction.removingPrivateOrFilePrivateModifier(keyword: \.funcKeyword) {
					context.diagnose(Diagnostic(
						node: Syntax(mockFunction),
						error: FixableInstantiableError.privateOrFilePrivateMockMethod(accessLevel),
						changes: [
							.replace(
								oldNode: Syntax(mockFunction),
								newNode: Syntax(fixedMockFunction),
							),
						],
					))
				}
				let mockFunctionInitializer = Initializer(mockFunction)
				if mockFunctionInitializer.isAsync || mockFunctionInitializer.doesThrow {
					context.diagnose(Self.mockMethodHasEffectSpecifiersDiagnostic(for: mockFunction))
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
				   !matchingInstantiable.dependencies.isEmpty,
				   !visitor.hasNamesEncodedDifferently
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
								error: FixableInstantiableError.mockMethodMissingArguments(methodName: mockFunction.name.text, missingArguments),
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
					throw InstantiableError.extensionCannotBeRoot(
						instantiableType,
						instantiateParameters: rootDependencies,
					)
				}
			}
			if visitor.generatesDependencyTree, let instantiableType = visitor.instantiableType {
				throw InstantiableError.extensionCannotGenerateDependencyTree(instantiableType)
			}

			// A default-valued parameter of `instantiate(…)` is not a dependency, as for an initializer, so the
			// method gets the checks an initializer gets. As for an initializer, its defaults reach a generated
			// mock only when the type has no hand-written mock.
			for instantiateFunction in visitor.instantiateFunctions {
				Self.validateUnlabeledDefaultShape(
					functionSyntax: instantiateFunction.syntax.signature,
					arguments: instantiateFunction.initializer.arguments,
					dependencies: instantiateFunction.dependencies,
					diagnosticNode: Syntax(instantiateFunction.syntax),
					context: context,
				)
				if visitor.mockInitializer == nil {
					Self.validateDefaultExpressions(
						functionSyntax: instantiateFunction.syntax.signature,
						dependencies: instantiateFunction.dependencies,
						typeName: extendedTypeName,
						context: context,
					)
					Self.validateReservedParameterLabels(
						functionSyntax: instantiateFunction.syntax.signature,
						dependencies: instantiateFunction.dependencies,
						context: context,
					)
				}
			}

			let instantiables = visitor.instantiables
			if instantiables.count > 1 {
				var concreteInstantiables = Set<TypeDescription>()
				for concreteInstantiable in instantiables.map(\.concreteInstantiable) {
					if concreteInstantiables.contains(concreteInstantiable) {
						throw InstantiableError.tooManyInstantiateMethods(
							concreteInstantiable,
							count: instantiables.count(where: { $0.concreteInstantiable == concreteInstantiable }),
						)
					} else {
						concreteInstantiables.insert(concreteInstantiable)
					}
				}
			} else if instantiables.isEmpty, !isMockOnly {
				let extendedTypeName = extensionDeclaration.extendedType.typeDescription.asSource
				let accessModifier = Self.accessModifierOfDeclarationAdded(to: extensionDeclaration, besideInstantiateMethods: [], takingParametersOf: [])
				var membersWithInitializer = declaration.memberBlock.members
				membersWithInitializer.insert(
					MemberBlockItemSyntax(
						leadingTrivia: .newline,
						decl: FunctionDeclSyntax(
							modifiers: DeclModifierListSyntax(ofAddedDeclarationWithAccess: accessModifier, isStatic: true),
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
						accessModifier: accessModifier,
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
		} else if ProtocolDeclSyntax(declaration) != nil {
			throw InstantiableError.decoratingProtocol
		} else {
			throw InstantiableError.decoratingIncompatibleType
		}
	}

	/// Diagnoses initializer/mock signatures that SafeDI's mock override
	/// surface cannot express: a non-dependency `_`-labeled defaulted
	/// parameter followed by a required (non-defaulted) `_`-labeled
	/// parameter. Eliding the earlier defaulted slot to let Swift's
	/// default-argument thunk fire would produce an uncallable signature
	/// (Swift requires the positional value when a later positional arg is
	/// required); exposing the defaulted parameter on
	/// `SafeDIMockConfiguration` isn't possible either because there's no
	/// external label to use as a struct field name.
	///
	/// Subsequent `_`-labeled parameters that also have defaults don't
	/// block elision — they're elided together as a trailing run — so
	/// signatures like `init(_ a: Int = 0, _ b: Int = 1)` are fine.
	private static func validateUnlabeledDefaultShape(
		functionSyntax: FunctionSignatureSyntax,
		arguments: [Initializer.Argument],
		dependencies: [Dependency],
		diagnosticNode: Syntax,
		context: some MacroExpansionContext,
	) {
		let dependencyLabels = Set(dependencies.map(\.property.label))
		let parameterSyntaxes = Array(functionSyntax.parameterClause.parameters)
		for (index, argument) in arguments.enumerated() {
			guard argument.label == "_",
			      argument.hasDefaultValue,
			      !dependencyLabels.contains(argument.innerLabel), let following = arguments[(index + 1)...].first(where: {
			      	$0.label == "_" && !$0.hasDefaultValue
			      }) else { continue }

			// Fix-it: promote the inner label to the external label by
			// rewriting `_ x: T = …` to `x: T = …`. That makes the parameter
			// callable by keyword, so eliding it from the mock override
			// surface becomes safe. Reordering or removing the default are
			// the other two resolutions the diagnostic message mentions;
			// users can apply those manually.
			var changes: [FixIt.Change] = []
			if index < parameterSyntaxes.count {
				let parameter = parameterSyntaxes[index]
				var fixedParameter = parameter
				fixedParameter.firstName = TokenSyntax.identifier(
					argument.innerLabel,
					leadingTrivia: parameter.firstName.leadingTrivia,
					trailingTrivia: parameter.firstName.trailingTrivia,
				)
				fixedParameter.secondName = nil
				changes.append(.replace(
					oldNode: Syntax(parameter),
					newNode: Syntax(fixedParameter),
				))
			}

			context.diagnose(Diagnostic(
				node: diagnosticNode,
				error: FixableInstantiableError.unlabeledDefaultBeforeUnlabeledParameter(
					defaultedParameter: argument.asProperty,
					followingParameter: following.asProperty,
				),
				changes: changes,
			))
		}
	}

	/// Walks each default-value expression on `functionSyntax`'s parameters and
	/// diagnoses any explicit reference to `Self`. SafeDI's generated mock
	/// surface may promote the default onto the caller's override struct
	/// (inside another type's extension), where `Self` binds to the caller's
	/// type instead of the decorated type — silently producing the wrong value
	/// or failing to typecheck. Unqualified references to callee-scope members
	/// can't be identified without type resolution and are not covered.
	///
	/// Two exemptions skip parameters whose defaults never reach the override
	/// surface:
	/// - Dependency parameters, which are always threaded explicitly at the
	///   mock call site.
	/// - `_`-labeled non-dependency parameters, which `ScopeGenerator` elides
	///   from call-site arguments and excludes from `rootDefaultParameters`,
	///   so Swift's default-argument thunk fires in the callee where `Self`
	///   resolves correctly.
	private static func validateDefaultExpressions(
		functionSyntax: FunctionSignatureSyntax,
		dependencies: [Dependency],
		typeName: String,
		context: some MacroExpansionContext,
	) {
		let dependencyLabels = Set(dependencies.map(\.property.label))
		for parameter in functionSyntax.parameterClause.parameters {
			guard let defaultValue = parameter.defaultValue?.value else { continue }
			let firstName = parameter.firstName.text
			let innerName = parameter.secondName ?? parameter.firstName
			guard !dependencyLabels.contains(innerName.spelledAsParameterName) else { continue }
			// `_`-labeled non-dependency defaults are elided from the mock
			// call site, so the default is evaluated in the callee's scope.
			guard firstName != "_" else { continue }
			// A generated mock takes the value as a parameter of its own and passes it on, which an
			// `@autoclosure` parameter, evaluated where it is called, cannot take.
			if let attributedType = AttributedTypeSyntax(parameter.type),
			   attributedType.attributes.contains(where: { AttributeSyntax($0)?.attributeName.trimmedDescription == "autoclosure" })
			{
				context.diagnose(Diagnostic(
					node: Syntax(parameter),
					message: FixableInstantiableError.defaultValuedAutoclosureParameter(parameterLabel: innerName.text).diagnostic,
				))
			}
			let finder = SelfReferenceFinder(viewMode: .sourceAccurate)
			finder.walk(Syntax(defaultValue))
			guard finder.containsSelfReference else { continue }
			context.diagnose(Diagnostic(
				node: Syntax(parameter),
				message: FixableInstantiableError.calleeScopeReferenceInDefaultExpression(
					parameterLabel: innerName.text,
					typeName: typeName,
				).diagnostic,
			))
		}
	}

	/// Diagnoses each parameter that SafeDI binds by a reserved argument label (`ReservedName`):
	/// a default-valued parameter with an argument label that fulfills no dependency. A generated
	/// `mock()` of the type takes such a parameter under that label and passes it on by name,
	/// beside the names generated code introduces. The parameters `validateDefaultExpressions`
	/// checks are exactly these.
	private static func validateReservedParameterLabels(
		functionSyntax: FunctionSignatureSyntax,
		dependencies: [Dependency],
		context: some MacroExpansionContext,
	) {
		let dependencyLabels = Set(dependencies.map(\.property.label))
		let parameters = functionSyntax.parameterClause.parameters
		for parameter in parameters where parameter.defaultValue != nil
			&& !dependencyLabels.contains((parameter.secondName ?? parameter.firstName).spelledAsParameterName)
		{
			let label = parameter.firstName
			if let reservation = ReservedName(reserving: label.text) {
				let error = FixableInstantiableError.reservedName(name: label.text, reservation: reservation)
				let labelsInUse = dependencyLabels.union(
					parameters.lazy
						.filter { $0.id != parameter.id }
						.map(\.firstName.spelledAsParameterName),
				)
				if let fixedParameter = renamingReservedLabel(of: parameter, reservedAs: reservation, labelsInUse: labelsInUse) {
					context.diagnose(Diagnostic(
						node: label,
						error: error,
						changes: [
							.replace(
								oldNode: Syntax(parameter),
								newNode: Syntax(fixedParameter),
							),
						],
					))
				} else {
					context.diagnose(Diagnostic(
						node: label,
						message: error.diagnostic,
					))
				}
			}
		}
	}

	/// `parameter` with its reserved argument label renamed, or `nil` when no rename is sound.
	///
	/// Only a label that begins with `ReservedName.builderFunctionNamePrefix` has an evident new
	/// label: the label without the prefix. An exactly reserved label has none, and any label the
	/// macro chose for it would be arbitrary.
	///
	/// The rename changes the argument label alone. The parameter keeps its name inside the
	/// function, so the function body still compiles and the parameter still fulfills no
	/// dependency; only a call that spells the old label must change, and the compiler reports it.
	/// It is not offered when the new label is not a valid variable name, is itself reserved, or is
	/// in `labelsInUse`, the labels of the dependencies and of the function's other parameters,
	/// which a generated `mock()` would then declare twice.
	private static func renamingReservedLabel(
		of parameter: FunctionParameterSyntax,
		reservedAs reservation: ReservedName,
		labelsInUse: Set<String>,
	) -> FunctionParameterSyntax? {
		switch reservation {
		case .mockOverridesParameter, .configurationBuilderProperty, .constructedType:
			return nil
		case .builderFunctionName:
			let label = parameter.firstName
			let newLabel = ReservedName.removingBuilderFunctionNamePrefix(from: label.text)
			guard newLabel.isValidSwiftIdentifier(for: .variableName),
			      ReservedName(reserving: newLabel) == nil,
			      !labelsInUse.contains(newLabel)
			else {
				return nil
			}
			var fixedParameter = parameter
			if let name = parameter.secondName {
				if name.text == newLabel {
					// `__safeDI_count count` becomes `count`, not the redundant `count count`.
					fixedParameter.firstName = .identifier(newLabel, leadingTrivia: label.leadingTrivia, trailingTrivia: name.trailingTrivia)
					fixedParameter.secondName = nil
				} else {
					fixedParameter.firstName = label.with(\.tokenKind, .identifier(newLabel))
				}
			} else {
				// `__safeDI_count` becomes `count __safeDI_count`, so the body's uses still resolve.
				fixedParameter.firstName = .identifier(newLabel, leadingTrivia: label.leadingTrivia, trailingTrivia: .space)
				fixedParameter.secondName = .identifier(label.text, trailingTrivia: label.trailingTrivia)
			}
			return fixedParameter
		}
	}

	/// Walks a default-value expression and sets `containsSelfReference` if
	/// any `Self` reference is encountered — expression-level (bare `Self`,
	/// `Self.member`, `Self(...)`) or type-level (`Optional<Self>`, `[Self]`,
	/// `(Self, T)`, etc.). Type-level occurrences are checked via
	/// `TypeDescription.containsSelf`, which recurses through generics,
	/// wrappers, composed types, tuples, and closures; expression-level
	/// occurrences are caught by matching any `DeclReferenceExprSyntax` whose
	/// name is `Self`.
	private final class SelfReferenceFinder: SyntaxVisitor {
		private(set) var containsSelfReference = false

		override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
			if node.baseName.text == "Self" {
				containsSelfReference = true
			}
			return .visitChildren
		}

		override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
			if TypeSyntax(node).typeDescription.containsSelf {
				containsSelfReference = true
			}
			return .visitChildren
		}
	}

	/// Diagnoses each dependency whose type names a type declared among `declarations` through `Self`, such as
	/// `Self.Config`. Generated code spells a dependency's type as its declaration does, and the code that builds or
	/// receives the dependency for another type – that type's initializer, an `Instantiator`'s builder, or that type's
	/// `mock()` – lives in an extension of that other type, where `Self` names the other type. SafeDITool qualifies a
	/// nested type's bare name (`Config`) wherever a declaration spells it, but never a spelling through `Self`, so only
	/// that spelling is diagnosed. An alias's `ofType:` argument spells the type of the property it renames, which
	/// generated code spells too, so it is checked with the dependency's type. The diagnostic is a warning because the
	/// declaration compiles while only its own `mock()`, which lives in an extension of `enclosingType`, names the type.
	///
	/// Each dependency gets one diagnostic, naming every such type, and one fix-it, which qualifies all of them in the
	/// dependency's type, its `ofType:` argument, and the type of each parameter with the dependency's name among
	/// `functionSignatures`, since SafeDI matches a parameter to a dependency by its spelled type. Within the decorated
	/// declaration the qualified name names the same type, so the change is safe wherever it is made.
	/// - Parameters:
	///   - dependencies: Each dependency's name and the syntax that spells its type.
	///   - functionSignatures: The initializers and hand-written mocks whose parameters fulfill the dependencies.
	///   - declarations: The members of the decorated declaration, with those in each clause of its `#if` blocks.
	///   - enclosingType: The decorated type with every type that encloses it, which the fix-it writes in place of
	///     `Self`.
	private static func diagnoseNestedTypesSpelledThroughSelf(
		in dependencies: [DependencyTypeSyntax],
		fulfilledByParametersOf functionSignatures: [FunctionSignatureSyntax],
		declaredAmong declarations: [DeclSyntax],
		enclosingType enclosingTypeDescription: TypeDescription,
		context: some MacroExpansionContext,
	) {
		// Sorted so that a diagnostic names the types in the same order every time.
		let nestedTypeNames = Set(declarations.compactMap(\.nestedTypeName)).sorted()
		func namesSpelledThroughSelf(in typeDescription: TypeDescription) -> [String] {
			nestedTypeNames.filter { typeName in typeDescription.namesType(where: { $0.starts(with: ["Self", typeName]) }) }
		}
		let enclosingTypeName = enclosingTypeDescription.asSource
		let enclosingType = TypeSyntax(IdentifierTypeSyntax(name: .identifier(enclosingTypeName)))
		let parameters = functionSignatures.flatMap(\.parameterClause.parameters)
		for dependency in dependencies {
			// The syntax spelling the dependency's type, and its alias's `ofType:` argument, that names a nested type
			// through `Self`.
			let typeSyntaxes: [(syntax: Syntax, typeDescription: TypeDescription)] = [(Syntax(dependency.type), dependency.type.typeDescription)]
				+ (dependency.aliasedType.map { [(Syntax($0), $0.typeDescription)] } ?? [])
			let diagnosedSyntaxes = typeSyntaxes.map { syntax, typeDescription in
				(syntax: syntax, typeNames: namesSpelledThroughSelf(in: typeDescription))
			}.filter { !$0.typeNames.isEmpty }
			if let diagnosedSyntax = diagnosedSyntaxes.first?.syntax {
				let typeNames = nestedTypeNames.filter { typeName in
					diagnosedSyntaxes.contains { $0.typeNames.contains(typeName) }
				}
				let dependencyLabel = dependency.name.spelledAsParameterName
				let fulfillingParameterTypes = parameters
					.filter { ($0.secondName ?? $0.firstName).spelledAsParameterName == dependencyLabel }
					.map(\.type)
					.filter { !namesSpelledThroughSelf(in: $0.typeDescription).isEmpty }
				let qualifier = NestedTypeThroughSelfQualifier(typeNames: Set(typeNames), enclosingType: enclosingType)
				context.diagnose(Diagnostic(
					node: diagnosedSyntax,
					error: FixableInstantiableError.nestedTypeSpelledThroughSelf(
						typeNames: typeNames.map {
							(spelling: "Self.\($0)", qualifiedSpelling: "\(enclosingTypeName).\($0)")
						},
					),
					changes: (diagnosedSyntaxes.map(\.syntax) + fulfillingParameterTypes.map(Syntax.init)).map { syntax in
						.replace(
							oldNode: syntax,
							newNode: qualifier.rewrite(syntax),
						)
					},
				))
			}
		}
	}

	/// The type named `name` that the macro decorates, with each type that encloses it, as code outside them spells
	/// it: `Feature.Child` for a `Child` declared in `enum Feature`. The macro's lexical context lists the declarations
	/// enclosing the decorated one, innermost first; an extension among them is declared at file scope, so it is the
	/// outermost and spells its extended type in full.
	private static func qualifiedType(named name: String, in context: some MacroExpansionContext) -> TypeDescription {
		var enclosingType: TypeDescription?
		// A type declared in a function cannot be named outside it, so the types around that function do not qualify it.
		for lexicalContext in context.lexicalContext.prefix(while: { $0.isProtocol(DeclGroupSyntax.self) }).reversed() {
			if let extensionDeclaration = ExtensionDeclSyntax(lexicalContext) {
				enclosingType = extensionDeclaration.extendedType.typeDescription
			} else if let typeDeclaration = lexicalContext.asProtocol(NamedDeclSyntax.self) {
				enclosingType = enclosingType.map {
					.nested(name: typeDeclaration.name.text, parentType: $0)
				} ?? .simple(name: typeDeclaration.name.text)
			}
		}
		return enclosingType.map {
			.nested(name: name, parentType: $0)
		} ?? .simple(name: name)
	}

	// MARK: - Access of Added Declarations

	/// The access modifier of a declaration that a fix-it adds to the type declaration `declaration` – an initializer or a
	/// hand-written mock method – that takes a parameter for each of `dependencies`, or `nil` when it spells none.
	///
	/// Generated code calls the added declaration wherever it constructs the type, so the declaration takes the type's
	/// access, as far as the macro can see it: the level the type spells – or, when it spells none, the default of the
	/// members of an extension it is directly inside, and `internal` otherwise – capped by the level of each type
	/// declaration enclosing it, found in the same way. An extension caps nothing, as
	/// `AccessLevel.effective(ofTypeDeclaredBy:)` describes. The members of a type declaration are `internal` unless they
	/// spell another level. See `accessModifier(ofDeclarationAddedWithTypeLevel:memberDefaultLevel:members:declaredType:dependencies:)`.
	private static func accessModifierOfDeclarationAdded(
		to declaration: some ConcreteDeclSyntaxProtocol,
		takingParametersOf dependencies: [Dependency],
		context: some MacroExpansionContext,
	) -> AccessLevel? {
		// The declarations enclosing `declaration`, innermost first, up to a function, outside which a type declared in
		// the function cannot be used.
		let enclosingDeclarations = Array(
			context.lexicalContext.lazy
				.map { $0.asProtocol(DeclGroupSyntax.self) }
				.prefix(while: { $0 != nil })
				.compactMap(\.self),
		)
		func ownLevel(ofTypeDeclarationWith modifiers: DeclModifierListSyntax, directlyInside enclosingDeclaration: (any DeclGroupSyntax)?) -> AccessLevel {
			modifiers.spelledAccessLevel
				?? enclosingDeclaration.flatMap { ExtensionDeclSyntax(Syntax($0)) }?.modifiers.spelledAccessLevel?.asDefaultOfExtensionMembers
				?? .internal
		}
		var typeLevel = ownLevel(ofTypeDeclarationWith: declaration.modifiers, directlyInside: enclosingDeclarations.first)
		for (index, enclosingDeclaration) in enclosingDeclarations.enumerated() where ExtensionDeclSyntax(Syntax(enclosingDeclaration)) == nil {
			typeLevel = typeLevel.capped(by: ownLevel(
				ofTypeDeclarationWith: enclosingDeclaration.modifiers,
				directlyInside: enclosingDeclarations.dropFirst(index + 1).first,
			))
		}
		return accessModifier(
			ofDeclarationAddedWithTypeLevel: typeLevel,
			memberDefaultLevel: .internal,
			members: declaration.memberBlock.members,
			declaredType: qualifiedType(named: declaration.name.text, in: context),
			dependencies: dependencies,
		)
	}

	/// The access modifier of a declaration that a fix-it adds to the extension `declaration` – an `instantiate()` method
	/// or a hand-written mock method – that takes a parameter for each of `dependencies`, or `nil` when it spells none.
	///
	/// The extension declares a type that is declared elsewhere, whose access the macro cannot see, so the added
	/// declaration takes the access of the widest of `instantiateMethods`, which construct the type and which a mock
	/// method stands in for, or, when there are none, the default of the extension's members: the level the extension
	/// spells (`fileprivate` for a `private` extension), and `internal` when it spells none. See
	/// `accessModifier(ofDeclarationAddedWithTypeLevel:memberDefaultLevel:members:declaredType:dependencies:)`.
	private static func accessModifierOfDeclarationAdded(
		to declaration: ExtensionDeclSyntax,
		besideInstantiateMethods instantiateMethods: [InstantiableVisitor.InstantiateFunction],
		takingParametersOf dependencies: [Dependency],
	) -> AccessLevel? {
		let memberDefaultLevel = declaration.modifiers.spelledAccessLevel?.asDefaultOfExtensionMembers ?? .internal
		return accessModifier(
			ofDeclarationAddedWithTypeLevel: instantiateMethods.map { $0.syntax.modifiers.spelledAccessLevel ?? memberDefaultLevel }.max() ?? memberDefaultLevel,
			memberDefaultLevel: memberDefaultLevel,
			members: declaration.memberBlock.members,
			declaredType: declaration.extendedType.typeDescription,
			dependencies: dependencies,
		)
	}

	/// The access modifier of a declaration that a fix-it adds to a declaration of `declaredType`, whose members are
	/// `members`, that takes a parameter for each of `dependencies`, or `nil` when it spells none.
	///
	/// The compiler requires a declaration to be no more visible than the types its parameters name, so the added
	/// declaration has `typeLevel` capped by the level of each type declared among `members` that a dependency's type
	/// names. The macro cannot see the level of a type declared anywhere else, so such a type caps nothing. The level is
	/// never narrower than `internal`, since generated code in another file calls the added declaration, nor wider than
	/// `public`, since an initializer or a static method cannot be `open`. The added declaration spells no access
	/// modifier where its level is `memberDefaultLevel`, the level of a member of the declaration that spells none.
	private static func accessModifier(
		ofDeclarationAddedWithTypeLevel typeLevel: AccessLevel,
		memberDefaultLevel: AccessLevel,
		members: MemberBlockItemListSyntax,
		declaredType: TypeDescription,
		dependencies: [Dependency],
	) -> AccessLevel? {
		let declaredTypeNamePath = declaredType.namePath
		let level = nestedTypes(declaredAmong: members, defaultLevel: memberDefaultLevel, enclosingPath: [], cappedBy: typeLevel)
			.filter { nestedType in
				dependencies.contains { dependency in
					dependency.property.typeDescription.namesType { path in
						// A path names the nested type when it ends with the nested type's path from the declared type,
						// qualified with nothing, which code inside the declaration resolves to the nested type, with
						// `Self`, or with the declared type's names from the innermost, as `Feature.Configuration` and
						// `Outer.Feature.Configuration` are.
						let qualifier = path.dropLast(nestedType.path.count)
						return path.suffix(nestedType.path.count).elementsEqual(nestedType.path)
							&& (qualifier.isEmpty
								|| qualifier.elementsEqual(["Self"])
								|| declaredTypeNamePath?.suffix(qualifier.count).elementsEqual(qualifier) == true)
					}
				}
			}
			.reduce(typeLevel) { $0.capped(by: $1.level) }
		let addedLevel = max(.internal, level.capped(by: .public))
		return addedLevel == memberDefaultLevel ? nil : addedLevel
	}

	/// Each type declared among `members`, in every clause of an `#if` block, and each type declared inside one of
	/// those, with its path from the declaration that holds `members`, and its level capped by `enclosingLevel` and by
	/// the level of each type it is declared inside. A type that spells no level has `defaultLevel`, the level of a
	/// member that spells none, and a type declared inside it `internal`.
	private static func nestedTypes(
		declaredAmong members: MemberBlockItemListSyntax,
		defaultLevel: AccessLevel,
		enclosingPath: [String],
		cappedBy enclosingLevel: AccessLevel,
	) -> [(path: [String], level: AccessLevel)] {
		declarations(in: members).flatMap { declaration -> [(path: [String], level: AccessLevel)] in
			guard let nestedTypeName = declaration.nestedTypeName,
			      let modifiers = declaration.asProtocol(WithModifiersSyntax.self)?.modifiers
			else {
				return []
			}
			let path = enclosingPath + [nestedTypeName]
			let level = (modifiers.spelledAccessLevel ?? defaultLevel).capped(by: enclosingLevel)
			let typesDeclaredInside = declaration.asProtocol(DeclGroupSyntax.self).map {
				nestedTypes(declaredAmong: $0.memberBlock.members, defaultLevel: .internal, enclosingPath: path, cappedBy: level)
			} ?? []
			return [(path: path, level: level)] + typesDeclaredInside
		}
	}

	/// The signatures of the hand-written mocks that `visitor` found, whose parameters fulfill the dependencies as an
	/// initializer's do.
	private static func mockFunctionSignatures(foundBy visitor: InstantiableVisitor) -> [FunctionSignatureSyntax] {
		([visitor.mockFunctionSyntax].compactMap(\.self) + visitor.duplicateMockFunctionSyntaxes).map(\.signature)
	}

	/// The declarations among `members`, with those in every clause of each `#if` block among them, as
	/// `InstantiableVisitor` scans the clauses of a declaration the macro decorates.
	private static func declarations(in members: MemberBlockItemListSyntax) -> [DeclSyntax] {
		members.flatMap { member in
			if let ifConfigDeclaration = IfConfigDeclSyntax(member.decl) {
				ifConfigDeclaration.clauses
					.compactMap { $0.elements?.as(MemberBlockItemListSyntax.self) }
					.flatMap(declarations(in:))
			} else {
				[member.decl]
			}
		}
	}

	private static func generateForwardedProperties(
		from forwardedProperties: [Property],
	) -> [DeclSyntax] {
		if forwardedProperties.isEmpty {
			[]
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
						initializer: TypeInitializerClauseSyntax(value: forwardedProperties.asForwardedPropertiesType),
					),
				),
			]
		}
	}

	// MARK: - Mock Method Effect Specifiers Fix-It

	/// The error for a hand-written mock method that is `async` or `throws`, which a generated mock calls
	/// synchronously, with a fix-it that removes its effect specifiers.
	private static func mockMethodHasEffectSpecifiersDiagnostic(for mockFunction: FunctionDeclSyntax) -> Diagnostic {
		var fixedMockFunction = mockFunction
		fixedMockFunction.signature.effectSpecifiers = nil
		return Diagnostic(
			node: Syntax(mockFunction),
			error: FixableInstantiableError.mockMethodHasEffectSpecifiers(methodName: mockFunction.name.text),
			changes: [
				.replace(
					oldNode: Syntax(mockFunction),
					newNode: Syntax(fixedMockFunction),
				),
			],
		)
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
		// Append remaining non-required parameters (e.g., extra parameters with defaults), in source order.
		for parameter in original.parameters where existingParameters[Initializer.Argument(parameter).asProperty] == parameter {
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

	/// The `generateMock:` argument's value as the attribute spells it, or `true` when it spells none.
	private static func spelling(ofGenerateMockArgumentOf attribute: AttributeSyntax) -> String {
		attribute.generateMock?.trimmedDescription ?? "true"
	}

	/// A change that replaces the `generateMock:` argument's value with `replacement`, keeping its trivia.
	private static func replacing(_ generateMockArgument: ExprSyntax, with replacement: String) -> FixIt.Change {
		.replace(
			oldNode: Syntax(generateMockArgument),
			newNode: Syntax(ExprSyntax("\(raw: replacement)")
				.with(\.leadingTrivia, generateMockArgument.leadingTrivia)
				.with(\.trailingTrivia, generateMockArgument.trailingTrivia)),
		)
	}

	/// Diagnoses `generateMock: .public` on a type declaration whose public `mock()` SafeDI cannot generate: one with
	/// a generic parameter clause, one declared in the body of a type that has one, and one that is not `public` or
	/// `open` – unless it spells no access level and sits directly inside a `public extension`, whose default it takes.
	/// A `private` or `fileprivate` type is reported by `privateOrFilePrivateType` alone.
	private static func validatePublicMockGeneration(
		of concreteDeclaration: some ConcreteDeclSyntaxProtocol,
		genericParameterClause: GenericParameterClauseSyntax?,
		instantiableMacro: AttributeSyntax,
		context: some MacroExpansionContext,
	) {
		guard instantiableMacro.mockGenerationValue == .public,
		      let generateMockArgument = instantiableMacro.generateMock
		else {
			return
		}
		let typeName = concreteDeclaration.name.text
		let enclosingDeclarations = context.lexicalContext.prefix(while: { $0.isProtocol(DeclGroupSyntax.self) })
		let enclosingGenericTypeName = enclosingDeclarations.lazy.compactMap { enclosingDeclaration -> String? in
			if let structDeclaration = StructDeclSyntax(enclosingDeclaration), structDeclaration.genericParameterClause != nil {
				structDeclaration.name.text
			} else if let classDeclaration = ClassDeclSyntax(enclosingDeclaration), classDeclaration.genericParameterClause != nil {
				classDeclaration.name.text
			} else if let actorDeclaration = ActorDeclSyntax(enclosingDeclaration), actorDeclaration.genericParameterClause != nil {
				actorDeclaration.name.text
			} else if let enumDeclaration = EnumDeclSyntax(enclosingDeclaration), enumDeclaration.genericParameterClause != nil {
				enumDeclaration.name.text
			} else {
				nil
			}
		}.first
		if genericParameterClause != nil || enclosingGenericTypeName != nil {
			context.diagnose(Diagnostic(
				node: Syntax(generateMockArgument),
				error: FixableInstantiableError.publicMockOnGenericType(typeName: typeName, genericTypeName: genericParameterClause == nil ? enclosingGenericTypeName : nil),
				changes: [Self.replacing(generateMockArgument, with: ".internal")],
			))
			return
		}
		let accessModifier = concreteDeclaration.modifiers.first { modifier in
			switch modifier.name.tokenKind {
			case .keyword(.open), .keyword(.public), .keyword(.package), .keyword(.internal), .keyword(.fileprivate), .keyword(.private):
				true
			default:
				false
			}
		}
		let accessLevel: AccessLevel = switch accessModifier?.name.tokenKind {
		case .keyword(.open): .open
		case .keyword(.public): .public
		case .keyword(.package): .package
		case .keyword(.fileprivate): .fileprivate
		case .keyword(.private): .private
		default: .internal
		}
		switch accessLevel {
		case .open, .public, .fileprivate, .private:
			return
		case .package, .internal:
			break
		}
		if accessModifier == nil,
		   let enclosingExtension = enclosingDeclarations.first.flatMap({ ExtensionDeclSyntax($0) }),
		   enclosingExtension.modifiers.contains(where: { $0.name.tokenKind == .keyword(.public) })
		{
			return
		}
		var publicDeclaration = concreteDeclaration
		if let accessModifier, let index = publicDeclaration.modifiers.firstIndex(where: { $0.id == accessModifier.id }) {
			publicDeclaration.modifiers[index].name = .keyword(
				.public,
				leadingTrivia: accessModifier.name.leadingTrivia,
				trailingTrivia: accessModifier.name.trailingTrivia,
			)
		} else if let firstModifier = publicDeclaration.modifiers.first {
			publicDeclaration.modifiers = DeclModifierListSyntax(
				[DeclModifierSyntax(name: .keyword(.public, leadingTrivia: firstModifier.leadingTrivia, trailingTrivia: .space))]
					+ publicDeclaration.modifiers.map { $0.with(\.leadingTrivia, []) },
			)
		} else {
			publicDeclaration.modifiers = DeclModifierListSyntax([
				DeclModifierSyntax(name: .keyword(.public, leadingTrivia: publicDeclaration.keyword.leadingTrivia, trailingTrivia: .space)),
			])
			publicDeclaration.keyword.leadingTrivia = []
		}
		let error = FixableInstantiableError.publicMockRequiresPublicType(
			typeName: typeName,
			accessLevel: accessLevel,
			isSpelled: accessModifier != nil,
		)
		context.diagnose(Diagnostic(
			node: Syntax(generateMockArgument),
			message: error.diagnostic,
			fixIts: [
				FixIt(
					message: error.fixIt,
					changes: [.replace(oldNode: Syntax(concreteDeclaration), newNode: Syntax(publicDeclaration))],
				),
				FixIt(
					message: MockGenerationArgumentFixItMessage(replacement: ".internal"),
					changes: [Self.replacing(generateMockArgument, with: ".internal")],
				),
			],
		))
	}

	/// Builds fix-it changes that remove a labeled argument from an `@Instantiable` attribute.
	private static func removeArgument(
		labeled label: String,
		from attribute: AttributeSyntax,
		on declaration: some SyntaxProtocol,
	) -> [FixIt.Change] {
		var fixedAttribute = attribute
		// safedi-source-rule: allow forceUnwrap — callers remove an argument only from an attribute whose accessor for its label (`generateMockValue`, `isRootValue`, `generateDependencyTree`, `mockAttributes`) read it from labeled arguments.
		let arguments = LabeledExprListSyntax(attribute.arguments!)!
		// safedi-source-rule: allow forceUnwrap — the arguments hold `label`, for the reason above.
		let targetIndex = arguments.firstIndex(where: { $0.label?.text == label })!
		var newArguments = Array(arguments)
		let removedIndex = arguments.distance(from: arguments.startIndex, to: targetIndex)
		newArguments.remove(at: removedIndex)
		// Fix trailing commas: the new last argument must not have a trailing comma.
		if !newArguments.isEmpty, let lastIndex = newArguments.indices.last {
			newArguments[lastIndex].trailingComma = nil
		}
		fixedAttribute.arguments = .argumentList(LabeledExprListSyntax(newArguments))
		let rewriter = AttributeRewriter(oldID: attribute.id, replacement: fixedAttribute)
		let fixedDeclaration = rewriter.rewrite(Syntax(declaration))
		return [.replace(oldNode: Syntax(declaration), newNode: fixedDeclaration)]
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
		// safedi-source-rule: allow forceUnwrap — callers rename only for an attribute whose `generateMockValue` read `generateMock: true` from its labeled arguments.
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
	/// - Parameter accessModifier: The level the method's access modifier sets, or `nil` for no access modifier, as
	///   `accessModifierOfDeclarationAdded(to:takingParametersOf:context:)` and
	///   `accessModifierOfDeclarationAdded(to:besideInstantiateMethods:takingParametersOf:)` return it.
	private static func generateCustomMockStub(
		named name: String,
		typeName: String,
		dependencies: [Dependency],
		accessModifier: AccessLevel?,
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
			return "\(dependency.property.label.spelledAsArgumentLabel): \(dependency.property.label)\(trailingComma)"
		}.joined()
		let construction = if isExtension {
			"\(typeName).\(InstantiableVisitor.instantiateMethodName)(\(argumentList))"
		} else {
			"\(typeName)(\(argumentList))"
		}

		let stubMethod = FunctionDeclSyntax(
			modifiers: DeclModifierListSyntax(ofAddedDeclarationWithAccess: accessModifier, isStatic: true),
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
		case decoratingProtocol
		case fulfillingAdditionalTypesContainsOptional(String)
		case fulfillingAdditionalTypesArgumentInvalid
		case generatedInitializerAttributesArgumentInvalid
		case mockAttributesArgumentInvalid
		case generatedAttributesArgumentInvalid
		case generateMockArgumentInvalid
		case mockOnlyArgumentInvalid
		case generateDependencyTreeArgumentInvalid
		case customMockNameArgumentInvalid
		case tooManyInstantiateMethods(TypeDescription, count: Int)
		case cannotBeRoot(TypeDescription, violatingDependencies: [Dependency])
		case extensionCannotBeRoot(TypeDescription, instantiateParameters: [Dependency])
		case extensionCannotGenerateDependencyTree(TypeDescription)

		var description: String {
			switch self {
			case .decoratingIncompatibleType:
				"@\(InstantiableVisitor.macroName) must decorate a class, struct, or actor declaration, or an extension of a type."
			case .decoratingProtocol:
				"@\(InstantiableVisitor.macroName) must decorate a class, struct, or actor declaration, or an extension of a type. To fulfill a protocol, decorate a type that conforms to it and list the protocol in `fulfillingAdditionalTypes`."
			case let .fulfillingAdditionalTypesContainsOptional(element):
				"The argument `fulfillingAdditionalTypes` must not include optional types, but it includes `\(element)`. List the non-optional type instead."
			case .fulfillingAdditionalTypesArgumentInvalid:
				"The argument `fulfillingAdditionalTypes` must be an array literal of types, such as `[MyProtocol.self]`."
			case .generatedInitializerAttributesArgumentInvalid:
				"The argument `generatedInitializerAttributes` must be a string literal."
			case .mockAttributesArgumentInvalid:
				"The argument `mockAttributes` must be a string literal."
			case .generatedAttributesArgumentInvalid:
				"The argument `generatedAttributes` must be a string literal."
			case .generateMockArgumentInvalid:
				"The argument `generateMock` must be `true`, `false`, `.none`, `.internal`, or `.public`."
			case .mockOnlyArgumentInvalid:
				"The argument `mockOnly` must be a Bool literal (`true` or `false`)."
			case .generateDependencyTreeArgumentInvalid:
				"The argument `generateDependencyTree` must be a Bool literal (`true` or `false`)."
			case .customMockNameArgumentInvalid:
				"The argument `customMockName` must be a string literal or `nil`."
			case let .tooManyInstantiateMethods(type, count):
				"@\(InstantiableVisitor.macroName)-decorated extension must have a single `\(InstantiableVisitor.instantiateMethodName)(…)` method that returns `\(type.asSource)`, but it has \(count). Remove all but one."
			case let .cannotBeRoot(declaredRootType, violatingDependencies):
				"`\(declaredRootType.asSource)` is declared with `isRoot: true`, so no other type passes it dependencies, but it needs \(violatingDependencies.asBacktickedPropertyList) from outside it. Declare each as @\(Dependency.Source.instantiatedRawValue), or as `@\(Dependency.Source.receivedRawValue)(fulfilledByDependencyNamed:ofType:)` naming an @\(Dependency.Source.instantiatedRawValue) property of `\(declaredRootType.asSource)`, or remove `isRoot: true` and instantiate `\(declaredRootType.asSource)` from another type, or replace `isRoot: true` with `generateDependencyTree: true`, so its generated initializer takes them."
			case let .extensionCannotBeRoot(declaredRootType, instantiateParameters):
				"`\(declaredRootType.asSource)` is declared with `isRoot: true`, so no other type passes it dependencies, but its `\(InstantiableVisitor.instantiateMethodName)(…)` method takes \(instantiateParameters.asBacktickedPropertyList). Remove the parameters, or remove `isRoot: true` and instantiate `\(declaredRootType.asSource)` from another type."
			case let .extensionCannotGenerateDependencyTree(extendedType):
				"`\(extendedType.asSource)` is declared with `generateDependencyTree: true` on an extension, but SafeDI generates a dependency tree only for a type declaration: an extension's `\(InstantiableVisitor.instantiateMethodName)(…)` method takes every dependency it needs, and SafeDI cannot add an initializer that builds them to a type it does not declare. Remove `generateDependencyTree: true`, or declare the dependency tree on an @\(InstantiableVisitor.macroName) type that instantiates `\(extendedType.asSource)`."
			}
		}
	}
}

// MARK: - [Dependency]

extension [Dependency] {
	/// The dependencies’ properties as a comma-separated list, each spelled as source in backticks.
	fileprivate var asBacktickedPropertyList: String {
		map { "`\($0.property.asSource)`" }.joined(separator: ", ")
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

// MARK: - DeclSyntax

extension DeclSyntax {
	/// The name of the type this declares – a struct, class, actor, enum, protocol, or type alias – or `nil` when this
	/// declares no type.
	fileprivate var nestedTypeName: String? {
		guard isProtocol(DeclGroupSyntax.self) || `is`(TypeAliasDeclSyntax.self) else {
			return nil
		}
		return asProtocol(NamedDeclSyntax.self)?.name.text
	}
}

// MARK: EffectfulInitializerNote

/// The note at an initializer that is `async` or `throws`, which generated code, calling initializers synchronously,
/// cannot call.
private struct EffectfulInitializerNote: NoteMessage {
	let message = "SafeDI cannot construct the type with this initializer: generated code calls an initializer synchronously, so it must be neither `async` nor `throws`."
	let noteID = MessageID(domain: "SafeDIMacros", id: "effectfulInitializer")
}

// MARK: Initializer

extension Initializer {
	fileprivate enum FixableError: Comparable, Hashable {
		/// The initializer is `private` or `fileprivate`, the level it carries.
		case inaccessibleInitializer(AccessLevel)
		case missingArguments([Property])
		indirect case multiple([FixableError])

		// Compare in terms of delta from what SafeDI needs – smallest requires the smallest change to make satisfactory:
		// removing a modifier, then adding the fewest missing arguments, then fixing the fewest errors at once. Errors
		// of one kind and size are equivalent, which a strict weak ordering allows.
		fileprivate static func < (lhs: FixableError, rhs: FixableError) -> Bool {
			(lhs.kindRank, lhs.size) < (rhs.kindRank, rhs.size)
		}

		/// The order of the kinds of error, from the one that takes the smallest change to fix.
		private var kindRank: Int {
			switch self {
			case .inaccessibleInitializer:
				0
			case .missingArguments:
				1
			case .multiple:
				2
			}
		}

		/// How much an error of its kind takes to fix.
		private var size: Int {
			switch self {
			case .inaccessibleInitializer:
				0
			case let .missingArguments(arguments):
				arguments.count
			case let .multiple(errors):
				errors.count
			}
		}

		fileprivate enum ErrorToFix {
			case inaccessibleInitializer(AccessLevel)
			case missingArguments([Property])
		}

		fileprivate var asErrorToFix: ErrorToFix {
			switch self {
			case let .inaccessibleInitializer(accessLevel):
				.inaccessibleInitializer(accessLevel)
			case let .missingArguments(arguments):
				.missingArguments(arguments)
			case let .multiple(errors):
				// safedi-source-rule: allow forceUnwrap — `asFixableError` makes `.multiple` only of two or more errors.
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
		case let .inaccessibleInitializer(accessLevel):
			.inaccessibleInitializer(accessLevel)
		case let .multiple(errors):
			Self.fixableError(combining: errors.compactMap(\.asFixableError))
		case .asyncInitializer,
		     .genericParameterInInitializer,
		     .optionalInitializer,
		     .throwingInitializer,
		     .unexpectedArgument,
		     .whereClauseOnInitializer:
			nil
		}
	}

	/// The error that `fixableErrors`, the fixable errors of one initializer, make together: none, the one, or – only
	/// when there are two or more – `multiple`, which therefore always has an error to fix first.
	private static func fixableError(combining fixableErrors: [Initializer.FixableError]) -> Initializer.FixableError? {
		if fixableErrors.count > 1 {
			.multiple(fixableErrors)
		} else {
			fixableErrors.first
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

// MARK: - DependencyTypeSyntax

/// A dependency's name and the syntax that spells its type.
private struct DependencyTypeSyntax {
	/// The property's name, or the inner name of an `instantiate(…)` parameter.
	let name: TokenSyntax
	let type: TypeSyntax
	/// The `ofType:` argument of an alias, which spells the type of the property the alias renames.
	let aliasedType: ExprSyntax?
}

// MARK: - NestedTypeThroughSelfQualifier

/// Writes each use of a nested type's name through `Self` with the type that declares it: `Self.Config` becomes
/// `Child.Config`, `Self.Config.Options` becomes `Child.Config.Options`, and `Self.Config.self` becomes
/// `Child.Config.self`, while `Config` and `Child.Config`, which SafeDI qualifies or which are qualified, are unchanged.
private final class NestedTypeThroughSelfQualifier: SyntaxRewriter {
	init(typeNames: Set<String>, enclosingType: TypeSyntax) {
		self.typeNames = typeNames
		self.enclosingType = enclosingType
		super.init(viewMode: .sourceAccurate)
	}

	override func visit(_ node: MemberTypeSyntax) -> TypeSyntax {
		guard IdentifierTypeSyntax(node.baseType)?.name.text == "Self", typeNames.contains(node.name.text) else {
			return super.visit(node)
		}
		return TypeSyntax(node
			.with(\.baseType, enclosingType.with(\.leadingTrivia, node.baseType.leadingTrivia))
			.with(\.genericArgumentClause, node.genericArgumentClause.map { visit($0) }))
	}

	override func visit(_ node: MemberAccessExprSyntax) -> ExprSyntax {
		// The member is named within its base, so only the base can need qualifying.
		if DeclReferenceExprSyntax(node.base)?.baseName.text == "Self", typeNames.contains(node.declName.baseName.text) {
			ExprSyntax(node.with(\.base, enclosingTypeExpression.with(\.leadingTrivia, node.leadingTrivia)))
		} else {
			ExprSyntax(node.with(\.base, node.base.map { visit($0) }))
		}
	}

	private let typeNames: Set<String>
	private let enclosingType: TypeSyntax

	private var enclosingTypeExpression: ExprSyntax {
		ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier(enclosingType.trimmedDescription)))
	}
}
