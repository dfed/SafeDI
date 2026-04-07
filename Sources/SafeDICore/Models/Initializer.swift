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

@preconcurrency import SwiftSyntax
import SwiftSyntaxBuilder

public struct Initializer: Codable, Hashable, Sendable {
	// MARK: Initialization

	init(_ node: InitializerDeclSyntax) {
		isPublicOrOpen = node.modifiers.containsPublicOrOpen
		isOptional = node.optionalMark != nil
		isAsync = node.signature.effectSpecifiers?.asyncSpecifier != nil
		doesThrow = node.signature.effectSpecifiers?.throwsClause?.throwsSpecifier != nil
		hasGenericParameter = node.genericParameterClause != nil
		hasGenericWhereClause = node.genericWhereClause != nil
		arguments = node
			.signature
			.parameterClause
			.parameters
			.map(Argument.init)
	}

	public init(_ node: FunctionDeclSyntax) {
		isPublicOrOpen = node.modifiers.containsPublicOrOpen
		isOptional = false
		isAsync = node.signature.effectSpecifiers?.asyncSpecifier != nil
		doesThrow = node.signature.effectSpecifiers?.throwsClause?.throwsSpecifier != nil
		hasGenericParameter = node.genericParameterClause != nil
		hasGenericWhereClause = node.genericWhereClause != nil
		arguments = node
			.signature
			.parameterClause
			.parameters
			.map(Argument.init)
	}

	init(
		isPublicOrOpen: Bool = true,
		isOptional: Bool = false,
		isAsync: Bool = false,
		doesThrow: Bool = false,
		hasGenericParameter: Bool = false,
		hasGenericWhereClause: Bool = false,
		arguments: [Initializer.Argument],
	) {
		self.isPublicOrOpen = isPublicOrOpen
		self.isOptional = isOptional
		self.isAsync = isAsync
		self.doesThrow = doesThrow
		self.hasGenericParameter = hasGenericParameter
		self.hasGenericWhereClause = hasGenericWhereClause
		self.arguments = arguments
	}

	// MARK: Public

	public let isPublicOrOpen: Bool
	public let isOptional: Bool
	public let isAsync: Bool
	public let doesThrow: Bool
	public let hasGenericParameter: Bool
	public let hasGenericWhereClause: Bool
	public let arguments: [Argument]

	public func isValid(forFulfilling dependencies: [Dependency]) -> Bool {
		do {
			try validate(fulfilling: dependencies, throwOnFirstError: true)
			return true
		} catch {
			return false
		}
	}

	public func validate(fulfilling dependencies: [Dependency], throwOnFirstError: Bool = false) throws(GenerationError) {
		var reasons = [GenerationError]()
		func recordError(_ generationError: GenerationError) throws(GenerationError) {
			if throwOnFirstError {
				throw generationError
			} else {
				reasons.append(generationError)
			}
		}
		if !isPublicOrOpen {
			try recordError(.inaccessibleInitializer)
		}
		if isOptional {
			try recordError(.optionalInitializer)
		}
		if isAsync {
			try recordError(.asyncInitializer)
		}
		if doesThrow {
			try recordError(.throwingInitializer)
		}
		if hasGenericParameter {
			try recordError(.genericParameterInInitializer)
		}
		if hasGenericWhereClause {
			try recordError(.whereClauseOnInitializer)
		}

		let dependencyAndArgumentBinding = try createDependencyAndArgumentBinding(given: dependencies)

		let initializerFulfulledDependencies = Set(dependencyAndArgumentBinding.map(\.dependency))
		let missingArguments = dependencies.filter { !initializerFulfulledDependencies.contains($0) }

		if !missingArguments.isEmpty {
			try recordError(.missingArguments(missingArguments.map(\.property)))
		}

		if reasons.count > 1 {
			throw .multiple(reasons)
		} else if let firstReason = reasons.first {
			throw firstReason
		}

		// We're good!
	}

	public func mapArguments(_ transform: (Argument) -> Argument) -> Self? {
		.init(
			isPublicOrOpen: isPublicOrOpen,
			isOptional: isOptional,
			isAsync: isAsync,
			doesThrow: doesThrow,
			hasGenericParameter: hasGenericParameter,
			hasGenericWhereClause: hasGenericWhereClause,
			arguments: arguments.map(transform),
		)
	}

	public static func generateRequiredInitializer(
		for dependencies: [Dependency],
		declarationType: ConcreteDeclType,
		andAdditionalPropertiesWithLabels additionalPropertyLabels: [String] = [],
	) -> InitializerDeclSyntax {
		InitializerDeclSyntax(
			modifiers: declarationType.initializerModifiers,
			signature: FunctionSignatureSyntax(
				parameterClause: FunctionParameterClauseSyntax(
					parameters: FunctionParameterListSyntax(itemsBuilder: {
						for functionParameter in dependencies.initializerFunctionParameters.enumerated().map({ index, parameter in
							var parameter = parameter
							if dependencies.initializerFunctionParameters.endIndex > 1 {
								if index == 0 {
									parameter.leadingTrivia = .newline
								}
								parameter.trailingTrivia = .newline
							}
							return parameter
						}) {
							functionParameter
						}
					}),
				),
				trailingTrivia: .space,
			),
			bodyBuilder: {
				for dependency in dependencies {
					dependency.property.asPropertyAssignment(withTrailingNewline: dependency == dependencies.last)
				}
				for (index, additionalPropertyLabel) in additionalPropertyLabels.enumerated() {
					CodeBlockItemSyntax(
						item: .expr(ExprSyntax(InfixOperatorExprSyntax(
							leadingTrivia: Trivia(
								pieces: [TriviaPiece.newlines(1)]
									+ (index == 0 ? [
										.lineComment("// The following properties are not decorated with the @\(Dependency.Source.instantiatedRawValue), @\(Dependency.Source.receivedRawValue), or @\(Dependency.Source.forwardedRawValue) macros, do not have default values, and are not computed properties."),
										TriviaPiece.newlines(1),
									] : []),
							),
							leftOperand: DeclReferenceExprSyntax(baseName: TokenSyntax.identifier(additionalPropertyLabel)),
							operator: AssignmentExprSyntax(
								leadingTrivia: .space,
								trailingTrivia: .space,
							),
							rightOperand: DeclReferenceExprSyntax(baseName: TokenSyntax.identifier("<#T##assign_\(additionalPropertyLabel)#>")),
							trailingTrivia: additionalPropertyLabel == additionalPropertyLabels.last ? .newline : nil,
						))),
					)
				}
			},
		)
	}

	// MARK: - Internal

	func createDependencyAndArgumentBinding(given dependencies: [Dependency]) throws(GenerationError) -> [(dependency: Dependency, argument: Argument)] {
		var bindings = [(dependency: Dependency, argument: Argument)]()
		for argument in arguments {
			guard let dependency = dependencies.first(where: {
				$0.property.label == argument.innerLabel
					&& $0.property.typeDescription.isEqualToFunctionArgument(argument.typeDescription)
			}) else {
				guard argument.hasDefaultValue else {
					throw GenerationError.unexpectedArgument(argument.asProperty.asSource)
				}
				// We do not care about this argument because it has a default value.
				continue
			}
			bindings.append((dependency: dependency, argument: argument))
		}
		return bindings
	}

	func createInitializerArgumentList(
		given dependencies: [Dependency],
		unavailableProperties: Set<Property>? = nil,
	) throws(GenerationError) -> String {
		try createDependencyAndArgumentBinding(given: dependencies)
			.map {
				if let unavailableProperties, unavailableProperties.contains($0.dependency.property) {
					"\($0.argument.label): nil"
				} else if $0.dependency.source == .forwarded {
					"\($0.argument.label): \($0.argument.innerLabel)"
				} else {
					"\($0.argument.label): \($0.argument.innerLabel)"
				}
			}
			.joined(separator: ", ")
	}

	/// Creates an argument list that includes ALL arguments — both dependency-matching
	/// and default-valued non-dependency arguments. Used in mock generation where
	/// default-valued parameters are bubbled up to the root mock method and
	/// dependency args are fulfilled from the tree.
	func createMockInitializerArgumentList(
		given dependencies: [Dependency],
		unavailableProperties: Set<Property>? = nil,
	) -> String {
		var parts = [String]()
		for argument in arguments {
			if let dependency = dependencies.first(where: {
				$0.property.label == argument.innerLabel
					&& $0.property.typeDescription.isEqualToFunctionArgument(argument.typeDescription)
			}) {
				if let unavailableProperties, unavailableProperties.contains(dependency.property) {
					parts.append("\(argument.label): nil")
				} else if dependency.source == .forwarded {
					// Forwarded deps use the bare parameter name — no remapping.
					parts.append("\(argument.label): \(argument.innerLabel)")
				} else {
					parts.append("\(argument.label): \(argument.innerLabel)")
				}
			} else if argument.hasDefaultValue, argument.label != "_" {
				parts.append("\(argument.label): \(argument.label)")
			}
			// Arguments that don't match a dependency and have no default are
			// caught by validate(fulfilling:) before mock code gen runs.
		}
		return parts.joined(separator: ", ")
	}

	// MARK: - GenerationError

	public enum GenerationError: Error, Equatable {
		case inaccessibleInitializer
		case asyncInitializer
		case throwingInitializer
		case optionalInitializer
		case genericParameterInInitializer
		case whereClauseOnInitializer
		/// The initializer is missing arguments for injected properties.
		case missingArguments([Property])
		/// The initializer has an argument that does not map to any injected properties.
		case unexpectedArgument(String)
		indirect case multiple([GenerationError])
	}

	// MARK: - Argument

	public struct Argument: Codable, Hashable, Sendable {
		/// The outer label, if one exists, by which the argument is referenced at the call site.
		public let outerLabel: String?
		/// The label by which the argument is referenced.
		public let innerLabel: String
		/// The type to which the property conforms.
		public let typeDescription: TypeDescription
		/// The source text of the default value expression, if one exists (e.g., `"nil"`, `".init()"`).
		public let defaultValueExpression: String?
		/// Whether the argument has a default value.
		public var hasDefaultValue: Bool {
			defaultValueExpression != nil
		}

		/// The label by which this argument is referenced at the call site.
		public var label: String {
			outerLabel ?? innerLabel
		}

		public var asProperty: Property {
			Property(
				label: innerLabel,
				typeDescription: typeDescription,
			)
		}

		public init(_ node: FunctionParameterSyntax) {
			if let secondName = node.secondName {
				outerLabel = node.firstName.text
				innerLabel = secondName.text
			} else {
				outerLabel = nil
				innerLabel = node.firstName.text
			}
			typeDescription = node.type.typeDescription
			defaultValueExpression = node.defaultValue?.value.trimmedDescription
		}

		init(outerLabel: String? = nil, innerLabel: String, typeDescription: TypeDescription, defaultValueExpression: String? = nil) {
			self.outerLabel = outerLabel
			self.innerLabel = innerLabel
			self.typeDescription = typeDescription
			self.defaultValueExpression = defaultValueExpression
		}

		public func withUpdatedTypeDescription(_ typeDescription: TypeDescription) -> Self {
			.init(
				outerLabel: outerLabel,
				innerLabel: innerLabel,
				typeDescription: typeDescription,
				defaultValueExpression: defaultValueExpression,
			)
		}

		static let dependenciesArgumentName: TokenSyntax = .identifier("buildSafeDIDependencies")
	}
}

// MARK: - ConcreteDeclType

extension ConcreteDeclType {
	fileprivate var initializerModifiers: DeclModifierListSyntax {
		DeclModifierListSyntax(
			arrayLiteral: DeclModifierSyntax(
				name: TokenSyntax(
					TokenKind.keyword(.public),
					presence: .present,
				),
				trailingTrivia: .space,
			),
		)
	}
}

// MARK: - TypeDescription

extension TypeDescription {
	fileprivate func isEqualToFunctionArgument(_ argument: TypeDescription) -> Bool {
		asFunctionParameter == argument
	}
}
