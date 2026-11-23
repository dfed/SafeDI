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

import SwiftParser
import SwiftSyntax

/// Rewrites one file. It reads the call sites and declarations of the file, the project's declarations, and the role
/// file, and nothing else: every edit it makes is decided by syntax and those roles.
final class MigrationRewriter: SyntaxRewriter {
	init(
		path: String,
		tree: SourceFileSyntax,
		typeIndex: MockedTypeIndex,
		declarations: SourceDeclarations,
		options: MigrationOptions,
		log: MigrationLog,
	) {
		self.path = path
		self.typeIndex = typeIndex
		self.declarations = declarations
		self.options = options
		self.log = log
		converter = SourceLocationConverter(fileName: path, tree: tree)
		let collector = ConfigurationValueCollector(viewMode: .sourceAccurate)
		collector.walk(tree)
		configurationValueNames = collector.names
		super.init(viewMode: .sourceAccurate)
	}

	/// What this rewriter and the ones before it did.
	private(set) var log: MigrationLog

	/// The configuration file created for a module that declares no `#SafeDIConfiguration`.
	static func newConfigurationFile(options: MigrationOptions) -> String {
		"import SafeDI\n\n#SafeDIConfiguration(\(options.optInArgumentLabel): \(options.optInArgumentValue))\n"
	}

	// MARK: Enclosing types

	override func visitPre(_ node: Syntax) {
		guard let parts = TypeDeclarationParts(node) else { return }
		typeStack.append(parts.name)
		findsMockByNameStack.append(InstantiableAttribute.findsMockByName(parts.attributes))
	}

	override func visitPost(_ node: Syntax) {
		guard TypeDeclarationParts(node) != nil else { return }
		typeStack.removeLast()
		findsMockByNameStack.removeLast()
	}

	// MARK: Declarations

	override func visit(_ node: FunctionDeclSyntax) -> DeclSyntax {
		let visited = super.visit(node)
		guard InstantiableAttribute.isStaticMock(node), findsMockByNameStack.last == true,
		      let function = visited.as(FunctionDeclSyntax.self)
		else { return visited }
		log.count(.handWrittenMockDeclarationRenamed)
		return DeclSyntax(function.with(\.name, Self.renamed(function.name, to: "fake")))
	}

	override func visit(_ node: AttributeSyntax) -> AttributeSyntax {
		guard node.attributeName.trimmedDescription == "Instantiable",
		      let arguments = node.arguments?.as(LabeledExprListSyntax.self)
		else { return super.visit(node) }
		let renamedArguments = LabeledExprListSyntax(arguments.map { argument in
			guard let label = argument.label, let renamed = Self.attributeLabelRenames[label.text] else { return argument }
			log.count(.attributeLabelRenamed)
			return argument.with(\.label, Self.renamed(label, to: renamed))
		})
		return super.visit(node.with(\.arguments, .argumentList(renamedArguments)))
	}

	override func visit(_ node: MacroExpansionDeclSyntax) -> DeclSyntax {
		super.visit(configurationOptingIn(node))
	}

	override func visit(_ node: MacroExpansionExprSyntax) -> ExprSyntax {
		super.visit(configurationOptingIn(node))
	}

	/// `node` with the 3.0 labels and the opt-in setting where it is a `#SafeDIConfiguration`, and as it is otherwise.
	private func configurationOptingIn<Node: FreestandingMacroExpansionSyntax>(_ node: Node) -> Node {
		guard node.macroName.text == "SafeDIConfiguration" else { return node }
		var arguments = [LabeledExprSyntax]()
		var hasOptIn = false
		for var argument in node.arguments {
			let label = argument.label?.text ?? ""
			if let renamed = Self.configurationLabelRenames[label], let token = argument.label {
				log.count(.configurationLabelRenamed)
				argument.label = Self.renamed(token, to: renamed)
			} else if label == options.optInArgumentLabel {
				hasOptIn = true
				if argument.expression.trimmedDescription != options.optInArgumentValue {
					log.count(.optInSettingUpdated)
					argument.expression = Self.expression(options.optInArgumentValue)
						.with(\.leadingTrivia, argument.expression.leadingTrivia)
						.with(\.trailingTrivia, argument.expression.trailingTrivia)
				}
			}
			arguments.append(argument)
		}
		if !hasOptIn {
			log.count(.optInSettingAdded)
			arguments.append(LabeledExprSyntax(
				leadingTrivia: Self.leadingTriviaOfNewArgument(in: node.arguments),
				label: .identifier(options.optInArgumentLabel),
				colon: .colonToken(trailingTrivia: .space),
				expression: Self.expression(options.optInArgumentValue),
			))
		}
		var rewritten = node
		rewritten.arguments = Self.argumentList(arguments, replacing: node.arguments)
		if rewritten.leftParen == nil {
			rewritten.leftParen = .leftParenToken()
			rewritten.rightParen = .rightParenToken(trailingTrivia: node.macroName.trailingTrivia)
			rewritten.macroName = node.macroName.with(\.trailingTrivia, [])
		}
		return rewritten
	}

	override func visit(_ node: VariableDeclSyntax) -> DeclSyntax {
		let isForwarded = node.attributes.contains {
			$0.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "Forwarded"
		}
		for binding in node.bindings where isForwarded {
			guard let type = binding.typeAnnotation?.type else { continue }
			let unwrapped = type.as(OptionalTypeSyntax.self)?.wrappedType ?? type
			guard let name = unwrapped.as(IdentifierTypeSyntax.self)?.name.text,
			      Self.safeDIWrapperNames.contains(name)
			else { continue }
			log.report(.forwardedWrapper, at: site(of: type), text: node.trimmedDescription)
		}
		return super.visit(node)
	}

	// MARK: Types and names

	override func visit(_ node: IdentifierTypeSyntax) -> TypeSyntax {
		guard let renamed = renamedTypeName(node.name.text) else { return super.visit(node) }
		return super.visit(node.with(\.name, Self.renamed(node.name, to: renamed)))
	}

	override func visit(_ node: MemberTypeSyntax) -> TypeSyntax {
		guard let renamed = renamedTypeName(node.name.text) else { return super.visit(node) }
		return super.visit(node.with(\.name, Self.renamed(node.name, to: renamed)))
	}

	override func visit(_ node: DeclReferenceExprSyntax) -> ExprSyntax {
		guard let renamed = renamedTypeName(node.baseName.text) else { return super.visit(node) }
		return super.visit(node.with(\.baseName, Self.renamed(node.baseName, to: renamed)))
	}

	override func visit(_ node: MemberAccessExprSyntax) -> ExprSyntax {
		if let base = node.base?.as(DeclReferenceExprSyntax.self), configurationValueNames.contains(base.baseName.text) {
			log.report(.configurationFieldRead, at: site(of: node), text: node.trimmedDescription)
		}
		let isCalled = node.parent?.as(FunctionCallExprSyntax.self)?.calledExpression.id == node.id
		if node.declName.baseName.text == "mock", !isCalled, let base = node.base,
		   typeIndex.resolve(base.trimmedDescription, enclosingTypes: typeStack) != nil
		{
			log.report(.mockReferencedAsValue, at: site(of: node), text: node.trimmedDescription)
		}
		return super.visit(node)
	}

	// MARK: Calls

	override func visit(_ node: FunctionCallExprSyntax) -> ExprSyntax {
		let visited = super.visit(node)
		guard let call = visited.as(FunctionCallExprSyntax.self),
		      let callee = MockCallee(call.calledExpression),
		      let resolution = resolution(of: callee, calledBy: node)
		else { return visited }
		let renamedCall = call.with(\.calledExpression, callee.renamed)
		switch resolution {
		case .handWritten:
			log.count(.handWrittenMockCallRenamed)
			return ExprSyntax(renamedCall)
		case .ambiguous:
			log.count(.generatedMockCallRenamed)
			log.report(.ambiguousType, at: site(of: node), text: node.trimmedDescription)
			return ExprSyntax(renamedCall)
		case let .generated(mockedType):
			log.count(.generatedMockCallRenamed)
			return ExprSyntax(migratingArguments(of: renamedCall, original: node, mockedType: mockedType))
		}
	}

	/// The type whose mock `callee` calls, or `nil` where it is no SafeDI mock or the rewriter cannot tell, which it
	/// reports.
	private func resolution(of callee: MockCallee, calledBy node: FunctionCallExprSyntax) -> MockedTypeIndex.Resolution? {
		switch callee {
		case .bare:
			return enclosingTypeResolution()
		case let .member(.some(base), _):
			let written = base.trimmedDescription
			if written == "Self" || written == "self" {
				return enclosingTypeResolution()
			} else if let resolution = typeIndex.resolve(written, enclosingTypes: typeStack) {
				return resolution
			} else {
				let first = String(written.split(separator: ".")[0])
				let standsForMockedType = declarations.genericParameterNames.contains(first)
					|| declarations.typealiasTargets[first].flatMap { typeIndex.resolve($0, enclosingTypes: []) } != nil
				if standsForMockedType {
					log.report(.typealiasOrGenericBase, at: site(of: node), text: node.trimmedDescription)
				}
				return nil
			}
		case .member(.none, _):
			guard let written = Self.contextualTypeName(of: node) else {
				log.report(.implicitMemberUnresolved, at: site(of: node), text: node.trimmedDescription)
				return nil
			}
			let resolution = typeIndex.resolve(written, enclosingTypes: typeStack)
			if resolution != nil {
				log.count(.implicitMemberResolvedFromWrittenType)
			}
			return resolution
		}
	}

	private func enclosingTypeResolution() -> MockedTypeIndex.Resolution? {
		guard !typeStack.isEmpty else { return nil }
		return typeIndex.resolution(of: typeStack.joined(separator: "."), inModule: nil)
	}

	/// Moves the arguments of a call of a generated mock to the 3.0 `fake()`'s parameters.
	private func migratingArguments(
		of call: FunctionCallExprSyntax,
		original: FunctionCallExprSyntax,
		mockedType: MigrationRoles.MockedType,
	) -> FunctionCallExprSyntax {
		guard call.trailingClosure == nil, call.additionalTrailingClosures.isEmpty else {
			log.report(.trailingClosure, at: site(of: original), text: original.trimmedDescription)
			return call
		}
		var flatParameters = [String: MigrationRoles.Parameter]()
		var parametersByOverridesField = [String: MigrationRoles.Parameter]()
		for parameter in mockedType.parameters {
			if parameter.role != .receivedBuildable || parameter.hasFlatParameter {
				flatParameters[parameter.label] = flatParameters[parameter.label] ?? parameter
			}
			if parameter.role == .receivedBuildable, let field = parameter.overridesField {
				parametersByOverridesField[field] = parametersByOverridesField[field] ?? parameter
			}
		}
		let overridesLabel = "safeDIOverrides"
		for argument in call.arguments where argument.label?.text != overridesLabel {
			guard flatParameters[argument.label?.text ?? ""] == nil else { continue }
			log.report(.unknownLabel, at: site(of: original), text: original.trimmedDescription)
			return call
		}
		let passedLabels = Set(call.arguments.compactMap { $0.label?.text })
		let overridesArgument = call.arguments.first { $0.label?.text == overridesLabel }
		let overridesLiteral = overridesArgument.flatMap { argument in
			argument.expression.as(FunctionCallExprSyntax.self).flatMap { Self.isOverridesLiteral($0) ? $0 : nil }
		}
		for field in overridesLiteral?.arguments ?? [] {
			guard let parameter = parametersByOverridesField[field.label?.text ?? ""],
			      passedLabels.contains(parameter.label)
			else { continue }
			log.report(.receivedBuildablePassedTwice, at: site(of: original), text: original.trimmedDescription)
			return call
		}
		let movesOwnDefaults = overridesArgument == nil || overridesLiteral != nil
		let rootDefaultLabels = mockedType.parameters.filter { $0.role == .rootDefault }.map(\.label)

		var keptArguments = [LabeledExprSyntax]()
		var movedDefaults = [(position: Int, argument: LabeledExprSyntax)]()
		for argument in call.arguments where argument.label?.text != overridesLabel {
			let label = argument.label?.text ?? ""
			let parameter = flatParameters[label] ?? MigrationRoles.Parameter(label: label, role: .forwarded)
			switch parameter.role {
			case .forwarded, .outsideValue, .holeBuilder, .publicMockBuilder:
				keptArguments.append(argument)
			case .uncovered:
				keptArguments.append(argument.with(\.expression, builder(of: argument, parameter: parameter, original: original)))
			case .rootDefault:
				if mockedType.isPublic, !parameter.isOptionalType, argument.expression.is(NilLiteralExprSyntax.self) {
					log.count(.publicNilDefaultDropped)
				} else if movesOwnDefaults {
					let fieldLabel = parameter.fieldLabel ?? label
					let moved = argument.label.map { argument.with(\.label, Self.renamed($0, to: fieldLabel)) } ?? argument
					movedDefaults.append((rootDefaultLabels.firstIndex(of: label) ?? 0, moved.with(\.trailingComma, nil).trimmed))
				} else {
					keptArguments.append(argument)
				}
			case .receivedBuildable:
				if argument.expression.is(NilLiteralExprSyntax.self) {
					log.count(.receivedNilDropped)
				} else {
					log.count(.receivedValueWrappedAsInstance)
					keptArguments.append(argument.with(\.expression, Self.wrapped(argument.expression, in: ".instance")))
				}
			}
		}
		if !movesOwnDefaults, rootDefaultLabels.contains(where: passedLabels.contains) {
			log.report(.ownDefaultBesideNonLiteralOverrides, at: site(of: original), text: original.trimmedDescription)
		}

		var builtArguments = [LabeledExprSyntax]()
		var newOverridesArgument = overridesArgument
		let ownDefaults = movedDefaults.sorted { $0.position < $1.position }.map(\.argument)
		if let overridesArgument, let overridesLiteral {
			var fields = [LabeledExprSyntax]()
			var removedField = false
			for field in overridesLiteral.arguments {
				guard let parameter = parametersByOverridesField[field.label?.text ?? ""] else {
					fields.append(field)
					continue
				}
				let configuration: ExprSyntax
				if let literal = field.expression.as(FunctionCallExprSyntax.self), Self.isConfigurationLiteral(literal) {
					configuration = field.expression.trimmed
				} else if field.expression.is(ClosureExprSyntax.self) {
					// A 2.x override closure is the configuration's builder in 3.0 (design note, "Migration rules settled after the rewriter spike").
					log.count(.receivedOverrideClosureMovedToBuilt)
					configuration = Self.wrapped(field.expression.trimmed, in: ".init")
				} else {
					log.report(.receivedBuildableOverrideNotLiteral, at: site(of: original), text: original.trimmedDescription)
					fields.append(field)
					continue
				}
				log.count(.receivedOverrideMovedToBuilt)
				removedField = true
				builtArguments.append(LabeledExprSyntax(
					leadingTrivia: Self.leadingTriviaOfNewArgument(in: call.arguments),
					label: .identifier(parameter.label),
					colon: .colonToken(trailingTrivia: .space),
					expression: Self.wrapped(configuration, in: ".built"),
				))
			}
			let newFieldTrivia = Self.leadingTriviaOfNewArgument(in: overridesLiteral.arguments)
			for ownDefault in ownDefaults {
				log.count(.ownDefaultMergedIntoOverrides)
				fields.append(ownDefault.with(\.leadingTrivia, newFieldTrivia))
			}
			if removedField, fields.isEmpty {
				newOverridesArgument = nil
			} else if removedField || !ownDefaults.isEmpty {
				let literal = overridesLiteral.with(\.arguments, Self.argumentList(fields, replacing: overridesLiteral.arguments))
				newOverridesArgument = overridesArgument.with(\.expression, ExprSyntax(literal))
			}
		} else if overridesArgument == nil, !ownDefaults.isEmpty {
			for _ in ownDefaults {
				log.count(.ownDefaultMovedIntoNewOverrides)
			}
			let literal = FunctionCallExprSyntax(
				calledExpression: Self.expression(".init"),
				leftParen: .leftParenToken(),
				arguments: Self.argumentList(ownDefaults, replacing: []),
				rightParen: .rightParenToken(),
			)
			newOverridesArgument = LabeledExprSyntax(
				leadingTrivia: Self.leadingTriviaOfNewArgument(in: call.arguments),
				label: .identifier(overridesLabel),
				colon: .colonToken(trailingTrivia: .space),
				expression: ExprSyntax(literal),
			)
		}

		var arguments = keptArguments + builtArguments
		if options.ordersArgumentsByRoleFile {
			let labelsInRoleOrder = mockedType.parameters.map(\.label)
			let ordered = arguments.enumerated().sorted {
				let lhs = labelsInRoleOrder.firstIndex(of: $0.element.label?.text ?? "") ?? 0
				let rhs = labelsInRoleOrder.firstIndex(of: $1.element.label?.text ?? "") ?? 0
				return (lhs, $0.offset) < (rhs, $1.offset)
			}
			if ordered.map(\.offset) != Array(arguments.indices) {
				log.count(.argumentsReordered)
				arguments = ordered.map(\.element)
			}
		}
		arguments += [newOverridesArgument].compactMap(\.self)
		return call.with(\.arguments, Self.argumentList(arguments, replacing: call.arguments))
	}

	/// The builder 3.0 takes for a created dependency the mock cannot build, from the value 2.x took.
	private func builder(
		of argument: LabeledExprSyntax,
		parameter: MigrationRoles.Parameter,
		original: FunctionCallExprSyntax,
	) -> ExprSyntax {
		let expression = argument.expression
		let text: String
		if parameter.isClosureType {
			log.report(.closureTypedDependencyWrapped, at: site(of: original), text: original.trimmedDescription)
		}
		if parameter.isSendableAutoclosure {
			// 2.x evaluated the autoclosure at each creation, as the builder does.
			log.count(.sendableAutoclosureWrapped)
			text = "{ \(expression.trimmedDescription) }"
		} else if !parameter.isClosureType, let name = expression.as(DeclReferenceExprSyntax.self)?.baseName.text,
		          let originalArgument = original.arguments.first(where: { $0.label?.text == parameter.label }),
		          LocalNames.isImmutableLocal(name, at: Syntax(originalArgument))
		{
			log.count(.createdDependencyWrappedLocalName)
			text = "{ \(name) }"
		} else {
			// Captured once, as 2.x evaluated the value once, and never `self`: a builder kept by a mock that a test
			// case stores would keep the test case alive.
			log.count(.createdDependencyWrappedCapturedExpression)
			let captureName = LocalNames.declarableName(parameter.label)
			text = "{ [\(captureName) = \(expression.trimmedDescription)] in \(captureName) }"
		}
		return Self.expression(text)
			.with(\.leadingTrivia, expression.leadingTrivia)
			.with(\.trailingTrivia, expression.trailingTrivia)
	}

	// MARK: Helpers

	private let path: String
	private let typeIndex: MockedTypeIndex
	private let declarations: SourceDeclarations
	private let options: MigrationOptions
	private let converter: SourceLocationConverter
	/// The names of this file's values typed as a 2.x configuration, whose fields 3.0 makes optional.
	private let configurationValueNames: Set<String>
	private var typeStack = [String]()
	private var findsMockByNameStack = [Bool]()

	private func site(of node: some SyntaxProtocol) -> SourceSite {
		let location = node.startLocation(converter: converter)
		return SourceSite(path: path, line: location.line, column: location.column)
	}

	private func renamedTypeName(_ name: String) -> String? {
		switch name {
		case "MockGeneration":
			log.count(.mockGenerationRenamed)
			return "FakeGeneration"
		case "SafeDIMockConfiguration":
			log.count(.configurationTypeRenamed)
			return "SafeDIFakeConfiguration"
		default:
			return nil
		}
	}

	private static let attributeLabelRenames = [
		"generateMock": "generateFake",
		"mockOnly": "fakeOnly",
		"mockAttributes": "fakeAttributes",
		"customMockName": "customFakeName",
	]
	private static let configurationLabelRenames = [
		"additionalMocksToGenerate": "additionalFakesToGenerate",
		"mockConditionalCompilation": "fakeConditionalCompilation",
	]
	private static let safeDIWrapperNames: Set = [
		"Instantiator",
		"ErasedInstantiator",
		"SendableInstantiator",
		"SendableErasedInstantiator",
		"LazilyInstantiated",
		"SendableLazilyInstantiated",
	]

	static func renamed(_ token: TokenSyntax, to name: String) -> TokenSyntax {
		.identifier(name, leadingTrivia: token.leadingTrivia, trailingTrivia: token.trailingTrivia)
	}

	static func expression(_ text: String) -> ExprSyntax {
		var parser = Parser(text)
		return ExprSyntax.parse(from: &parser)
	}

	static func wrapped(_ expression: ExprSyntax, in member: String) -> ExprSyntax {
		Self.expression("\(member)(\(expression.trimmedDescription))")
			.with(\.leadingTrivia, expression.leadingTrivia)
			.with(\.trailingTrivia, expression.trailingTrivia)
	}

	/// Whether `call` writes a 2.x `SafeDIOverrides` value field by field.
	static func isOverridesLiteral(_ call: FunctionCallExprSyntax) -> Bool {
		let callee = call.calledExpression.trimmedDescription
		return call.trailingClosure == nil
			&& (callee == ".init" || callee.hasSuffix("SafeDIOverrides") || callee.hasSuffix("SafeDIOverrides.init"))
	}

	/// Whether `call` writes a configuration of a type field by field, which 3.0's `.built(…)` takes.
	static func isConfigurationLiteral(_ call: FunctionCallExprSyntax) -> Bool {
		let callee = call.calledExpression.trimmedDescription
		return call.trailingClosure == nil
			&& (callee == ".init" || callee.hasSuffix("Configuration") || callee.hasSuffix("Configuration.init"))
	}

	/// The leading trivia an argument added to `arguments` takes: the last argument's where each starts a line.
	static func leadingTriviaOfNewArgument(in arguments: LabeledExprListSyntax) -> Trivia {
		guard let last = arguments.last, last.leadingTrivia.contains(where: \.isNewline) else { return [] }
		return last.leadingTrivia
	}

	/// `arguments` as a list in the place of `original`: each but the last followed by a comma, and the last by what
	/// followed the original's last.
	static func argumentList(_ arguments: [LabeledExprSyntax], replacing original: LabeledExprListSyntax) -> LabeledExprListSyntax {
		let isMultiLine = original.last?.leadingTrivia.contains(where: \.isNewline) ?? false
		var list = [LabeledExprSyntax]()
		for (index, argument) in arguments.enumerated() {
			if index < arguments.count - 1 {
				list.append(argument.trailingComma == nil
					? argument.with(\.trailingComma, .commaToken(trailingTrivia: isMultiLine ? [] : .space))
					: argument)
			} else {
				list.append(argument.with(\.trailingComma, original.last?.trailingComma))
			}
		}
		return LabeledExprListSyntax(list)
	}

	/// The type an implicit member expression is read as, where the source writes it: a binding's or parameter's type
	/// annotation, or the return type of the function or computed property whose body returns it.
	static func contextualTypeName(of node: FunctionCallExprSyntax) -> String? {
		func unwrapped(_ type: TypeSyntax) -> String {
			let wrapped = type.as(OptionalTypeSyntax.self)?.wrappedType
				?? type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self)?.wrappedType
				?? type
			return wrapped.trimmedDescription
		}
		let parent = node.parent
		if let initializer = parent?.as(InitializerClauseSyntax.self) {
			let type = initializer.parent?.as(PatternBindingSyntax.self)?.typeAnnotation?.type
				?? initializer.parent?.as(FunctionParameterSyntax.self)?.type
			return type.map(unwrapped)
		}
		let isReturned = parent?.is(ReturnStmtSyntax.self) == true
			|| parent?.as(CodeBlockItemSyntax.self)?.parent?.as(CodeBlockItemListSyntax.self)?.count == 1
		guard isReturned else { return nil }
		var ancestor = parent?.parent
		while let current = ancestor, !current.is(ClosureExprSyntax.self) {
			if let function = current.as(FunctionDeclSyntax.self) {
				return function.signature.returnClause.map { unwrapped($0.type) }
			} else if let binding = current.as(PatternBindingSyntax.self) {
				return binding.typeAnnotation.map { unwrapped($0.type) }
			}
			ancestor = current.parent
		}
		return nil
	}
}

/// How a call names a `mock` method.
private enum MockCallee {
	init?(_ calledExpression: ExprSyntax) {
		if let member = calledExpression.as(MemberAccessExprSyntax.self), member.declName.baseName.text == "mock" {
			self = .member(base: member.base, access: member)
		} else if let reference = calledExpression.as(DeclReferenceExprSyntax.self), reference.baseName.text == "mock" {
			self = .bare(reference)
		} else {
			return nil
		}
	}

	/// `mock(…)` inside the type.
	case bare(DeclReferenceExprSyntax)
	/// `T.mock(…)`, `Self.mock(…)`, or `.mock(…)`.
	case member(base: ExprSyntax?, access: MemberAccessExprSyntax)

	var renamed: ExprSyntax {
		switch self {
		case let .bare(reference):
			ExprSyntax(reference.with(\.baseName, MigrationRewriter.renamed(reference.baseName, to: "fake")))
		case let .member(_, access):
			ExprSyntax(access.with(\.declName.baseName, MigrationRewriter.renamed(access.declName.baseName, to: "fake")))
		}
	}
}

/// Finds the values of a file typed as a 2.x configuration.
private final class ConfigurationValueCollector: SyntaxVisitor {
	var names = Set<String>()

	override func visit(_ node: PatternBindingSyntax) -> SyntaxVisitorContinueKind {
		let typeText = node.typeAnnotation?.type.trimmedDescription
			?? node.initializer?.value.as(FunctionCallExprSyntax.self)?.calledExpression.trimmedDescription
		if let typeText, Self.namesConfiguration(typeText), let name = node.pattern.as(IdentifierPatternSyntax.self)?.identifier.text {
			names.insert(name)
		}
		return .visitChildren
	}

	override func visit(_ node: FunctionParameterSyntax) -> SyntaxVisitorContinueKind {
		if Self.namesConfiguration(node.type.trimmedDescription) {
			names.insert((node.secondName ?? node.firstName).text)
		}
		return .visitChildren
	}

	static func namesConfiguration(_ text: String) -> Bool {
		var components = text.split(separator: ".")
		while let last = components.last, last.hasSuffix("?") || last.hasSuffix("!") {
			components[components.count - 1] = last.dropLast()
		}
		if components.last == "init" {
			components.removeLast()
		}
		return components.last == "SafeDIOverrides" || components.last == "SafeDIMockConfiguration"
	}
}
