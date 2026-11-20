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

import Foundation
@preconcurrency import SwiftSyntax
import SwiftSyntaxBuilder

public struct Initializer: Codable, Hashable, Sendable {
	// MARK: Initialization

	/// - Parameter sourceLocationConverter: A converter for the tree that holds `node`. When provided, the initializer
	///   records where its access modifier is and where its declaration begins.
	init(_ node: InitializerDeclSyntax, sourceLocationConverter: SourceLocationConverter? = nil) {
		access = node.modifiers.access(introducedBy: node.initKeyword, sourceLocationConverter: sourceLocationConverter)
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
		spelledIsolation = Self.spelledIsolation(modifiers: node.modifiers, attributes: node.attributes)
	}

	/// - Parameter sourceLocationConverter: A converter for the tree that holds `node`. When provided, the initializer
	///   records where its access modifier is and where its declaration begins.
	public init(_ node: FunctionDeclSyntax, sourceLocationConverter: SourceLocationConverter? = nil) {
		access = node.modifiers.access(introducedBy: node.funcKeyword, sourceLocationConverter: sourceLocationConverter)
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
		spelledIsolation = Self.spelledIsolation(modifiers: node.modifiers, attributes: node.attributes)
	}

	public init(
		access: AccessDeclaration = AccessDeclaration(level: .public),
		isOptional: Bool = false,
		isAsync: Bool = false,
		doesThrow: Bool = false,
		hasGenericParameter: Bool = false,
		hasGenericWhereClause: Bool = false,
		arguments: [Initializer.Argument],
		spelledIsolation: String? = nil,
	) {
		self.access = access
		self.isOptional = isOptional
		self.isAsync = isAsync
		self.doesThrow = doesThrow
		self.hasGenericParameter = hasGenericParameter
		self.hasGenericWhereClause = hasGenericWhereClause
		self.arguments = arguments
		self.spelledIsolation = spelledIsolation
	}

	// MARK: Public

	/// The access the initializer's own modifiers spell, which begins at its first modifier or its `init` or `func`
	/// keyword. A method declared in an extension defaults to the extension's access (`fileprivate` for a `private`
	/// extension), which the `Instantiable` records.
	public let access: AccessDeclaration
	public let isOptional: Bool
	public let isAsync: Bool
	public let doesThrow: Bool
	public let hasGenericParameter: Bool
	public let hasGenericWhereClause: Bool
	public let arguments: [Argument]
	/// The isolation the declaration spells, which code that calls it from another declaration mirrors: `nonisolated`
	/// for the modifier, or a global actor attribute (an attribute whose name ends in `Actor`, such as `@MainActor`),
	/// or `nil` when it spells neither and takes its type's isolation.
	public let spelledIsolation: String?

	/// See `spelledIsolation`.
	/// The global actor attribute among `attributes`, a space-separated list of attributes as `mockAttributes` spells
	/// them (`"@MainActor"`), found as `spelledIsolation(modifiers:attributes:)` finds one: an attribute without
	/// arguments whose name ends in `Actor`.
	public static func globalActorAttribute(in attributes: String) -> String? {
		attributes.split(separator: " ").first { $0.hasPrefix("@") && !$0.contains("(") && $0.hasSuffix("Actor") }.map(String.init)
	}

	static func spelledIsolation(modifiers: DeclModifierListSyntax, attributes: AttributeListSyntax) -> String? {
		if modifiers.contains(where: { $0.name.tokenKind == .keyword(.nonisolated) }) {
			return "nonisolated"
		}
		// A loop rather than a lazy sequence, whose generic iterators cost more than reading the attributes: nearly every
		// declaration SafeDI reads has attributes and an initializer.
		for case let .attribute(attribute) in attributes where attribute.arguments == nil && spelledName(of: attribute.attributeName).hasSuffix("Actor") {
			return "@\(spelledName(of: attribute.attributeName))"
		}
		return nil
	}

	/// The text of `attributeName` without its leading and trailing trivia. A plain name, which nearly every attribute's
	/// is, is its token's text: building the trimmed text of any other name copies its syntax tree, which costs a scan
	/// more than the rest of reading the declaration does.
	private static func spelledName(of attributeName: TypeSyntax) -> String {
		if let identifierType = IdentifierTypeSyntax(attributeName),
		   identifierType.genericArgumentClause == nil,
		   identifierType.unexpectedBeforeName == nil,
		   identifierType.unexpectedBetweenNameAndGenericArgumentClause == nil,
		   identifierType.unexpectedAfterGenericArgumentClause == nil
		{
			identifierType.name.text
		} else {
			attributeName.trimmedDescription
		}
	}

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
		for error in dependencyIndependentErrors {
			try recordError(error)
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

	/// The names this initializer's parameters declare `@escaping`, each of which is a function type (`nameDeclaredEscaping`).
	var typesDeclaredEscaping: [TypeDescription] {
		arguments.compactMap(\.typeDescription.nameDeclaredEscaping)
	}

	public func mapArguments(_ transform: (Argument) -> Argument) -> Self? {
		.init(
			access: access,
			isOptional: isOptional,
			isAsync: isAsync,
			doesThrow: doesThrow,
			hasGenericParameter: hasGenericParameter,
			hasGenericWhereClause: hasGenericWhereClause,
			arguments: arguments.map(transform),
			spelledIsolation: spelledIsolation,
		)
	}

	/// The initializer the fix-it for a type without one adds: a parameter for each of `dependencies`, which it assigns
	/// to its property, and a placeholder assignment for each property labeled with one of `additionalPropertyLabels`.
	/// - Parameter accessLevel: The level the initializer's access modifier sets, or `nil` for no access modifier.
	public static func generateRequiredInitializer(
		for dependencies: [Dependency],
		accessLevel: AccessLevel?,
		andAdditionalPropertiesWithLabels additionalPropertyLabels: [String] = [],
	) -> InitializerDeclSyntax {
		InitializerDeclSyntax(
			modifiers: DeclModifierListSyntax(ofAddedDeclarationWithAccess: accessLevel, isStatic: false),
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

	/// Whether this initializer could fulfill the dependencies a declaration has under some evaluation
	/// of the `#if` blocks among its members. Every evaluation has each of `guaranteedDependencies`
	/// and none beyond `possibleDependencies`. Returns `false` only when no such evaluation exists.
	func couldBeValid(forFulfillingEvery guaranteedDependencies: [Dependency], amongPossible possibleDependencies: [Dependency]) -> Bool {
		// Each argument without a default must bind to a dependency, and each guaranteed dependency must be bound.
		dependencyIndependentErrors.isEmpty
			&& (try? createDependencyAndArgumentBinding(given: possibleDependencies)) != nil
			&& guaranteedDependencies.allSatisfy { dependency in
				arguments.contains { $0.isFulfilled(by: dependency) }
			}
	}

	func createDependencyAndArgumentBinding(given dependencies: [Dependency]) throws(GenerationError) -> [(dependency: Dependency, argument: Argument)] {
		// Only a dependency of an argument's label can fulfill it, so the dependencies are looked up by label, keeping their
		// order: searching every dependency for each argument makes a type of many dependencies quadratic.
		var dependenciesByLabel = [String: [Dependency]]()
		for dependency in dependencies {
			dependenciesByLabel[dependency.property.label, default: []].append(dependency)
		}
		var bindings = [(dependency: Dependency, argument: Argument)]()
		for argument in arguments {
			guard let dependency = dependenciesByLabel[argument.innerLabel]?.first(where: argument.isFulfilled(by:)) else {
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

	/// The arguments without a default value that none of `dependencies` is passed to, in declaration order, each with its
	/// position among `arguments`: those a call generated from `dependencies` cannot pass.
	func argumentsWithoutDefaultFulfilledByNone(of dependencies: [Dependency]) -> [(position: Int, argument: Argument)] {
		arguments.enumerated()
			.filter { !$0.element.hasDefaultValue && !dependencies.contains(where: $0.element.isFulfilled(by:)) }
			.map { (position: $0.offset, argument: $0.element) }
	}

	/// Creates an argument list that includes ALL arguments — both dependency-matching
	/// and default-valued non-dependency arguments. Used in mock generation where
	/// default-valued parameters are bubbled up to the root mock method and
	/// dependency arguments are fulfilled from the tree.
	/// A default-valued argument the mock leaves to its default (`Argument.isLeftToItsDefault`) is left out.
	func createMockInitializerArgumentList(
		given dependencies: [Dependency],
		unavailableProperties: Set<Property>? = nil,
	) -> String {
		var parts = [String]()
		for argument in arguments {
			if let dependency = dependencies.first(where: argument.isFulfilled(by:)) {
				if let unavailableProperties, unavailableProperties.contains(dependency.property) {
					parts.append("\(argument.label.spelledAsArgumentLabel): nil")
				} else {
					parts.append("\(argument.label.spelledAsArgumentLabel): \(argument.innerLabel)")
				}
			} else if argument.hasDefaultValue, !argument.isLeftToItsDefault {
				parts.append("\(argument.label.spelledAsArgumentLabel): \(argument.label)")
			}
			// Arguments that don't match a dependency and have no default are
			// caught by validate(fulfilling:) before mock code gen runs.
		}
		return parts.joined(separator: ", ")
	}

	// MARK: - Private

	/// The reasons this initializer cannot construct its type, whatever dependencies the type has. Generated code is
	/// always in a file of its own, so it cannot call a `private` or `fileprivate` initializer. Any other access can
	/// suit the code that constructs the type, which SafeDITool checks when it generates that code.
	private var dependencyIndependentErrors: [GenerationError] {
		[
			access.level.isPrivateOrFilePrivate ? .inaccessibleInitializer(access.level) : nil,
			isOptional ? .optionalInitializer : nil,
			isAsync ? .asyncInitializer : nil,
			doesThrow ? .throwingInitializer : nil,
			hasGenericParameter ? .genericParameterInInitializer : nil,
			hasGenericWhereClause ? .whereClauseOnInitializer : nil,
		].compactMap(\.self)
	}

	// MARK: - GenerationError

	public enum GenerationError: Error, Equatable {
		/// The initializer is `private` or `fileprivate`, the level it carries.
		case inaccessibleInitializer(AccessLevel)
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
		/// Whether the default value throws: holds a `try` that is neither `try?` nor `try!` outside every closure it
		/// declares, whose body throws to the closure's caller. Only a throwing `@autoclosure`'s default can throw, so no
		/// other argument's default is read for one. Decided from the default's syntax where the argument is parsed.
		public let defaultValueThrows: Bool
		/// Whether the argument has a default value.
		public var hasDefaultValue: Bool {
			defaultValueExpression != nil
		}

		/// Whether a generated mock leaves this argument to its default rather than take a value for it: an argument
		/// without a label, which a call does not name, and a throwing `@autoclosure` whose default itself throws
		/// (`defaultValueThrows`), which a mock could take only as a closure that throws, and so could not call where it
		/// builds the type, outside any function that throws. The initializer evaluates such a default itself, as in
		/// production.
		public var isLeftToItsDefault: Bool {
			hasDefaultValue && (label == "_" || defaultValueThrows)
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

		/// The property as `Property.asFunctionParamter` spells it when this argument takes that property: `asProperty`,
		/// without the `@escaping` of a name, which that spelling does not know a name needs.
		public var asFunctionParameterProperty: Property {
			Property(
				label: innerLabel,
				typeDescription: typeDescription.nameDeclaredEscaping ?? typeDescription,
			)
		}

		public init(_ node: FunctionParameterSyntax) {
			if let secondName = node.secondName {
				outerLabel = node.firstName.spelledAsParameterName
				innerLabel = secondName.spelledAsParameterName
			} else {
				outerLabel = nil
				innerLabel = node.firstName.spelledAsParameterName
			}
			typeDescription = node.type.typeDescription
			defaultValueExpression = node.defaultValue?.value.trimmedDescription
			defaultValueThrows = if let defaultValue = node.defaultValue, typeDescription.isThrowingAutoclosure {
				ThrowingTryVisitor.findsThrowingTry(in: defaultValue.value)
			} else {
				false
			}
		}

		public init(
			outerLabel: String? = nil,
			innerLabel: String,
			typeDescription: TypeDescription,
			defaultValueExpression: String? = nil,
			defaultValueThrows: Bool = false,
		) {
			self.outerLabel = outerLabel
			self.innerLabel = innerLabel
			self.typeDescription = typeDescription
			self.defaultValueExpression = defaultValueExpression
			self.defaultValueThrows = defaultValueThrows
		}

		public func withUpdatedTypeDescription(_ typeDescription: TypeDescription) -> Self {
			.init(
				outerLabel: outerLabel,
				innerLabel: innerLabel,
				typeDescription: typeDescription,
				defaultValueExpression: defaultValueExpression,
				defaultValueThrows: defaultValueThrows,
			)
		}

		static let dependenciesArgumentName: TokenSyntax = .identifier("buildSafeDIDependencies")

		/// Whether `dependency` is passed to this argument.
		func isFulfilled(by dependency: Dependency) -> Bool {
			dependency.property.label == innerLabel
				&& dependency.property.typeDescription.isEqualToFunctionArgument(typeDescription)
		}
	}
}

// MARK: - ThrowingTryVisitor

/// Finds a `try` that throws out of the expression it walks: one that is neither `try?` nor `try!`, outside every closure the
/// expression declares, whose body throws to the closure's caller.
private final class ThrowingTryVisitor: SyntaxVisitor {
	/// Whether `expression` holds a `try` that throws out of it.
	static func findsThrowingTry(in expression: ExprSyntax) -> Bool {
		let visitor = ThrowingTryVisitor(viewMode: .sourceAccurate)
		visitor.walk(expression)
		return visitor.findsThrowingTry
	}

	private var findsThrowingTry = false

	override func visit(_ node: TryExprSyntax) -> SyntaxVisitorContinueKind {
		// A `try?` or `try!` handles what any `try` inside it throws, and one plain `try` settles it.
		findsThrowingTry = findsThrowingTry || node.questionOrExclamationMark == nil
		return .skipChildren
	}

	override func visit(_: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
		.skipChildren
	}
}

// MARK: - TypeDescription

extension TypeDescription {
	/// Whether this is a throwing `@autoclosure`, the only parameter type whose default can throw.
	fileprivate var isThrowingAutoclosure: Bool {
		guard case let .attributed(.closure(_, _, doesThrow, _, _), _, attributes) = self else { return false }
		return doesThrow && attributes.contains("autoclosure")
	}

	/// Whether a parameter of type `argument` takes a property of this type: the parameter's type is this type as a
	/// function parameter (`asFunctionParameter`, which spells a closure type `@escaping`), with its attributes in any
	/// order, since Swift reads `@Sendable @escaping` and `@escaping @Sendable` as one type. Or the parameter's type is
	/// this name declared `@escaping` (`nameDeclaredEscaping`).
	fileprivate func isEqualToFunctionArgument(_ argument: TypeDescription) -> Bool {
		asFunctionParameter.withAttributesInSortedOrder == argument.withAttributesInSortedOrder
			|| argument.nameDeclaredEscaping == self
	}

	/// This type with the attributes that apply to it in sorted order, which Swift accepts in any order.
	private var withAttributesInSortedOrder: TypeDescription {
		switch self {
		case let .attributed(type, specifiers, attributes):
			.attributed(type, specifiers: specifiers, attributes: attributes.sorted())
		case .any,
		     .array,
		     .closure,
		     .composition,
		     .dictionary,
		     .implicitlyUnwrappedOptional,
		     .metatype,
		     .nested,
		     .optional,
		     .simple,
		     .some,
		     .tuple,
		     .unknown,
		     .variadic,
		     .void:
			self
		}
	}
}
