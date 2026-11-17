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

/// The values each local function declared at the top of an initializer's body captures, as Swift computes them: the
/// initializer's parameters and the `let`s of its body that the function reads, and everything each local function of
/// the body that it names captures in turn, since a local function that names another captures what that one captures.
/// A name the function declares itself, anywhere in its body, is read as that declaration: generated code declares a name
/// before it reads it, so a read of a name the function also declares never reads the body's.
enum LocalFunctionCaptures {
	/// The names each local function at the top of the body of every initializer of `source` whose parameters include one
	/// named `parameterName` captures, by the function's name.
	static func captures(inInitializerTaking parameterName: String, of source: String) -> [String: Set<String>] {
		let file = Parser.parse(source: source)
		var captures = [String: Set<String>]()
		for initializer in InitializerFinder(parameterName: parameterName, viewMode: .sourceAccurate).initializers(in: file) {
			guard let body = initializer.body else { continue }
			var capturableNames = Set(initializer.signature.parameterClause.parameters.map { ($0.secondName ?? $0.firstName).text })
			var functions = [String: FunctionDeclSyntax]()
			for item in body.statements {
				if let function = item.item.as(FunctionDeclSyntax.self) {
					functions[function.name.text] = function
				} else if let variable = item.item.as(VariableDeclSyntax.self) {
					for binding in variable.bindings {
						if let pattern = binding.pattern.as(IdentifierPatternSyntax.self) {
							capturableNames.insert(pattern.identifier.text)
						}
					}
				}
			}
			// What each function reads directly, and the functions it names.
			var directCaptures = [String: Set<String>]()
			var namedFunctions = [String: Set<String>]()
			for (name, function) in functions {
				let reads = NameReads(viewMode: .sourceAccurate).reads(in: function)
				let readNames = reads.read.subtracting(reads.declared)
				directCaptures[name] = readNames.intersection(capturableNames)
				namedFunctions[name] = readNames.intersection(functions.keys).subtracting([name])
			}
			// Each function's captures, to a fixed point over the functions it names.
			var functionCaptures = directCaptures
			var changed = true
			while changed {
				changed = false
				for (name, named) in namedFunctions {
					var current = functionCaptures[name, default: []]
					let count = current.count
					for other in named {
						current.formUnion(functionCaptures[other, default: []])
					}
					if current.count != count {
						functionCaptures[name] = current
						changed = true
					}
				}
			}
			captures.merge(functionCaptures) { first, second in first.union(second) }
		}
		return captures
	}

	/// Finds the initializers that take a parameter of a given name.
	private final class InitializerFinder: SyntaxVisitor {
		init(parameterName: String, viewMode: SyntaxTreeViewMode) {
			self.parameterName = parameterName
			super.init(viewMode: viewMode)
		}

		func initializers(in file: SourceFileSyntax) -> [InitializerDeclSyntax] {
			walk(file)
			return found
		}

		override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
			if node.signature.parameterClause.parameters.contains(where: { ($0.secondName ?? $0.firstName).text == parameterName }) {
				found.append(node)
			}
			return .skipChildren
		}

		private let parameterName: String
		private var found = [InitializerDeclSyntax]()
	}

	/// The names a function reads – each reference that is not the member of a member access – and the names it declares:
	/// its parameters, and every `let`, `var`, closure parameter and function in its body.
	private final class NameReads: SyntaxVisitor {
		func reads(in function: FunctionDeclSyntax) -> (read: Set<String>, declared: Set<String>) {
			for parameter in function.signature.parameterClause.parameters {
				declared.insert((parameter.secondName ?? parameter.firstName).text)
			}
			if let body = function.body {
				walk(body)
			}
			return (read, declared)
		}

		override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
			if let memberAccess = node.parent?.as(MemberAccessExprSyntax.self), memberAccess.declName.id == node.id {
				return .skipChildren
			}
			read.insert(node.baseName.text)
			return .skipChildren
		}

		override func visit(_ node: IdentifierPatternSyntax) -> SyntaxVisitorContinueKind {
			declared.insert(node.identifier.text)
			return .skipChildren
		}

		override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
			declared.insert(node.name.text)
			for parameter in node.signature.parameterClause.parameters {
				declared.insert((parameter.secondName ?? parameter.firstName).text)
			}
			return .visitChildren
		}

		override func visit(_ node: ClosureShorthandParameterSyntax) -> SyntaxVisitorContinueKind {
			declared.insert(node.name.text)
			return .skipChildren
		}

		private var read = Set<String>()
		private var declared = Set<String>()
	}
}
