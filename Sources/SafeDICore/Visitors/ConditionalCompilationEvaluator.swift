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

import SwiftSyntax

/// Selects the `#if` branch SafeDITool should scan without pretending to know
/// compiler flags the caller did not provide.
struct ConditionalCompilationEvaluator {
	let activeCompilationConditions: Set<String>

	func activeClause(in node: IfConfigDeclSyntax) -> ConditionalCompilationClauseSelection {
		for clause in node.clauses {
			guard let condition = clause.condition else {
				return .active(clause)
			}

			switch evaluate(condition) {
			case let .known(isActive):
				if isActive {
					return .active(clause)
				}
			case let .unknown(error):
				return .unevaluable(error)
			}
		}
		return .active(nil)
	}

	func evaluate(_ condition: ExprSyntax) -> ConditionalCompilationEvaluation {
		if let boolLiteral = BooleanLiteralExprSyntax(condition) {
			return .known(boolLiteral.literal.tokenKind == .keyword(.true))
		}

		if let identifier = DeclReferenceExprSyntax(condition) {
			let name = identifier.baseName.text
			if activeCompilationConditions.contains(name) {
				return .known(true)
			}
			// Missing custom flags are unknown, not false. The scanner can be
			// invoked outside the compiler command that ultimately defines `-D`
			// flags, so silently treating an absent flag as inactive would hide
			// guarded SafeDI declarations from generation.
			return .unknown(.init(condition: name, suggestedActiveCondition: name))
		}

		if let prefixOperator = PrefixOperatorExprSyntax(condition) {
			guard prefixOperator.operator.text == "!" else {
				return .unknown(.init(condition: condition.trimmedDescription))
			}
			return evaluate(prefixOperator.expression).negated
		}

		if let sequence = SequenceExprSyntax(condition) {
			return evaluateSequence(Array(sequence.elements), fallbackDescription: condition.trimmedDescription)
		}

		if let infixOperator = InfixOperatorExprSyntax(condition),
		   let binaryOperator = BinaryOperatorExprSyntax(infixOperator.operator)
		{
			let left = evaluate(infixOperator.leftOperand)
			let right = evaluate(infixOperator.rightOperand)
			switch binaryOperator.operator.text {
			case "&&":
				return left.and(right)
			case "||":
				return left.or(right)
			default:
				return .unknown(.init(condition: condition.trimmedDescription))
			}
		}

		if let tuple = TupleExprSyntax(condition),
		   tuple.elements.count == 1,
		   let element = tuple.elements.first
		{
			return evaluate(element.expression)
		}

		return .unknown(.init(condition: condition.trimmedDescription))
	}

	private func evaluateSequence(
		_ elements: [ExprSyntax],
		fallbackDescription: String,
	) -> ConditionalCompilationEvaluation {
		var index = 0

		func parseOr() -> ConditionalCompilationEvaluation {
			var result = parseAnd()
			while consumeOperator("||", elements: elements, index: &index) {
				result = result.or(parseAnd())
			}
			return result
		}

		func parseAnd() -> ConditionalCompilationEvaluation {
			var result = parsePrimary()
			while consumeOperator("&&", elements: elements, index: &index) {
				result = result.and(parsePrimary())
			}
			return result
		}

		func parsePrimary() -> ConditionalCompilationEvaluation {
			guard index < elements.count else {
				return .unknown(.init(condition: fallbackDescription))
			}
			let expression = elements[index]
			index += 1
			if BinaryOperatorExprSyntax(expression) != nil {
				return .unknown(.init(condition: fallbackDescription))
			}
			return evaluate(expression)
		}

		let result = parseOr()
		if index == elements.count {
			return result
		} else {
			return .unknown(.init(condition: fallbackDescription))
		}
	}

	private func consumeOperator(
		_ expectedOperator: String,
		elements: [ExprSyntax],
		index: inout Int,
	) -> Bool {
		guard index < elements.count,
		      let binaryOperator = BinaryOperatorExprSyntax(elements[index]),
		      binaryOperator.operator.text == expectedOperator
		else {
			return false
		}
		index += 1
		return true
	}
}

enum ConditionalCompilationClauseSelection {
	case active(IfConfigClauseSyntax?)
	case unevaluable(UnevaluableConditionalCompilationConditionError)
}

enum ConditionalCompilationEvaluation {
	case known(Bool)
	case unknown(UnevaluableConditionalCompilationConditionError)

	var negated: Self {
		switch self {
		case let .known(value):
			.known(!value)
		case .unknown:
			self
		}
	}

	func and(_ other: Self) -> Self {
		switch (self, other) {
		case (.known(false), _), (_, .known(false)):
			.known(false)
		case (.known(true), let other):
			other
		case (let selfEvaluation, .known(true)):
			selfEvaluation
		case (.unknown, _):
			self
		}
	}

	func or(_ other: Self) -> Self {
		switch (self, other) {
		case (.known(true), _), (_, .known(true)):
			.known(true)
		case (.known(false), let other):
			other
		case (let selfEvaluation, .known(false)):
			selfEvaluation
		case (.unknown, _):
			self
		}
	}
}

extension SyntaxVisitor {
	func walkIfConfigElements(_ elements: IfConfigClauseSyntax.Elements) {
		switch elements {
		case let .statements(statements):
			walk(statements)
		case let .switchCases(switchCases):
			walk(switchCases)
		case let .decls(decls):
			walk(decls)
		case let .postfixExpression(expression):
			walk(expression)
		case let .attributes(attributes):
			walk(attributes)
		}
	}
}

extension IfConfigDeclSyntax {
	var containsSafeDIDeclaration: Bool {
		let visitor = SafeDIDeclarationDetector()
		visitor.walk(self)
		return visitor.containsSafeDIDeclaration
	}

	func containsInstantiableBodySyntax(customMockName: String?) -> Bool {
		let visitor = InstantiableBodySyntaxDetector(customMockName: customMockName)
		visitor.walk(self)
		return visitor.containsInstantiableBodySyntax
	}
}

private final class SafeDIDeclarationDetector: SyntaxVisitor {
	init() {
		super.init(viewMode: .sourceAccurate)
	}

	var containsSafeDIDeclaration = false

	override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
		visitDecl(node)
	}

	override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
		visitDecl(node)
	}

	override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
		visitDecl(node)
	}

	override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
		if node.attributes.instantiableMacro != nil {
			containsSafeDIDeclaration = true
			return .skipChildren
		}
		return containsSafeDIDeclaration ? .skipChildren : .visitChildren
	}

	override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
		if !node.attributes.dependencySources.isEmpty {
			containsSafeDIDeclaration = true
		}
		return .skipChildren
	}

	override func visit(_ node: MacroExpansionDeclSyntax) -> SyntaxVisitorContinueKind {
		if node.macroName.text == SafeDIConfigurationVisitor.macroName {
			containsSafeDIDeclaration = true
		}
		return .skipChildren
	}

	override func visit(_ node: MacroExpansionExprSyntax) -> SyntaxVisitorContinueKind {
		if node.macroName.text == SafeDIConfigurationVisitor.macroName {
			containsSafeDIDeclaration = true
		}
		return .skipChildren
	}

	private func visitDecl(_ node: some ConcreteDeclSyntaxProtocol) -> SyntaxVisitorContinueKind {
		if node.attributes.instantiableMacro != nil {
			containsSafeDIDeclaration = true
			return .skipChildren
		}
		return containsSafeDIDeclaration ? .skipChildren : .visitChildren
	}
}

private final class InstantiableBodySyntaxDetector: SyntaxVisitor {
	init(customMockName: String?) {
		self.customMockName = customMockName
		super.init(viewMode: .sourceAccurate)
	}

	var containsInstantiableBodySyntax = false

	private let customMockName: String?

	override func visit(_: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
		containsInstantiableBodySyntax = true
		return .skipChildren
	}

	override func visit(_: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
		containsInstantiableBodySyntax = true
		return .skipChildren
	}

	override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
		if node.name.text == InstantiableVisitor.instantiateMethodName
			|| node.name.text == InstantiableVisitor.mockMethodName
			|| node.name.text == customMockName
		{
			containsInstantiableBodySyntax = true
		}
		return .skipChildren
	}

	override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
		visitDecl(node)
	}

	override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
		visitDecl(node)
	}

	override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
		visitDecl(node)
	}

	override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
		if node.attributes.instantiableMacro != nil {
			containsInstantiableBodySyntax = true
			return .skipChildren
		}
		return containsInstantiableBodySyntax ? .skipChildren : .visitChildren
	}

	private func visitDecl(_ node: some ConcreteDeclSyntaxProtocol) -> SyntaxVisitorContinueKind {
		if node.attributes.instantiableMacro != nil {
			containsInstantiableBodySyntax = true
			return .skipChildren
		}
		return containsInstantiableBodySyntax ? .skipChildren : .visitChildren
	}
}
