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

/// Which names an expression can read without capturing anything that changes or outlives the call.
enum LocalNames {
	/// Whether `name`, read at `node`, is a constant declared in the function or closure around it: a `let`, a
	/// parameter, an `if let` or `guard let` binding, or a `for` loop's element. Such a name is read by a closure as
	/// the value it holds at the call; a property is read through `self`, and a `var` when the closure runs.
	static func isImmutableLocal(_ name: String, at node: Syntax) -> Bool {
		var ancestor = node.parent
		while let current = ancestor, !current.is(MemberBlockSyntax.self) {
			if declares(name, current) {
				return true
			}
			ancestor = current.parent
		}
		return false
	}

	/// `label`, spelled so that it can be declared in a capture list.
	static func declarableName(_ label: String) -> String {
		Parser.parse(source: "let \(label) = 0").hasError ? "`\(label)`" : label
	}

	private static func declares(_ name: String, _ node: Syntax) -> Bool {
		if let items = node.as(CodeBlockItemListSyntax.self) {
			items.contains { item in
				if let variable = item.item.as(VariableDeclSyntax.self) {
					variable.bindingSpecifier.tokenKind == .keyword(.let)
						&& variable.bindings.contains { $0.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == name }
				} else if let guardStatement = item.item.as(GuardStmtSyntax.self) {
					bindsConstant(name, in: guardStatement.conditions)
				} else {
					false
				}
			}
		} else if let ifExpression = node.as(IfExprSyntax.self) {
			bindsConstant(name, in: ifExpression.conditions)
		} else if let forStatement = node.as(ForStmtSyntax.self) {
			forStatement.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == name
		} else if let function = node.as(FunctionDeclSyntax.self) {
			declaresParameter(name, in: function.signature.parameterClause.parameters)
		} else if let initializer = node.as(InitializerDeclSyntax.self) {
			declaresParameter(name, in: initializer.signature.parameterClause.parameters)
		} else if let closure = node.as(ClosureExprSyntax.self) {
			switch closure.signature?.parameterClause {
			case let .simpleInput(parameters):
				parameters.contains { $0.name.text == name }
			case let .parameterClause(clause):
				clause.parameters.contains { ($0.secondName ?? $0.firstName).text == name }
			case nil:
				false
			}
		} else {
			false
		}
	}

	private static func declaresParameter(_ name: String, in parameters: FunctionParameterListSyntax) -> Bool {
		parameters.contains { ($0.secondName ?? $0.firstName).text == name }
	}

	private static func bindsConstant(_ name: String, in conditions: ConditionElementListSyntax) -> Bool {
		conditions.contains { element in
			guard let binding = element.condition.as(OptionalBindingConditionSyntax.self) else { return false }
			return binding.bindingSpecifier.tokenKind == .keyword(.let)
				&& binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == name
		}
	}
}
