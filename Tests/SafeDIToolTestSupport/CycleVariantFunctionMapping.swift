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

/// The checked mapping between the code a root generates today and the code the per-type cycle build generates for it:
/// the per-type build may only drop functions that duplicate another, so each of its functions must equal, once names
/// are mapped, every function of today's code it stands for, and nothing else may differ.
///
/// Functions are matched by what they are, never by their names, which a layout chooses in the order it meets them.
/// The functions declared directly in one outermost body (an initializer's or a function's) of either file start in one
/// class per text, with every name of a function of that body left out; a class is then split until two functions of
/// one class call, in order, functions of the same classes. Each class must hold exactly one function of the per-type
/// code, or as many as it holds of today's, which then pair in declaration order. Today's code, with each of its
/// functions renamed to its counterpart and each declaration of a name declared earlier in its body dropped, must then
/// spell the per-type code byte for byte.
enum CycleVariantFunctionMapping {
	/// Every reason `perTypeCode` is no checked mapping of `todaysCode`, empty when it is one.
	static func problems(todaysCode: String, perTypeCode: String) -> [String] {
		// Today's functions capture what the per-type functions take as parameters, so neither side's parameters nor the
		// arguments of its calls are compared.
		let todaysCode = erasingParameters(of: todaysCode)
		let perTypeCode = erasingParameters(of: perTypeCode)
		let todaysFile = Parser.parse(source: todaysCode)
		let perTypeFile = Parser.parse(source: perTypeCode)
		let todaysBodies = OutermostBodies(viewMode: .sourceAccurate).bodies(in: todaysFile)
		let perTypeBodies = OutermostBodies(viewMode: .sourceAccurate).bodies(in: perTypeFile)
		guard todaysBodies.count == perTypeBodies.count else {
			return ["today’s code has \(todaysBodies.count) bodies, the per-type code \(perTypeBodies.count)"]
		}
		var problems = [String]()
		var renamings = [[String: String]]()
		for (index, (todaysBody, perTypeBody)) in zip(todaysBodies, perTypeBodies).enumerated() {
			switch renaming(from: todaysBody, to: perTypeBody) {
			case let .success(renaming):
				renamings.append(renaming)
			case let .failure(failure):
				problems.append(contentsOf: failure.problems.map { "body \(index): \($0)" })
				renamings.append([:])
			}
		}
		guard problems.isEmpty else { return problems }
		let mapped = MappingRewriter(renamings: renamings).rewrite(todaysFile).description
		guard mapped != perTypeCode else { return [] }
		return [firstDifference(mapped: mapped, perTypeCode: perTypeCode)]
	}

	/// `code` with every function declared in a body taking no parameters, every call of one passing no arguments, and a
	/// wrapper made of a closure that only calls one made of the function itself, as a wrapper of a function that takes
	/// nothing is.
	static func erasingParameters(of code: String) -> String {
		let file = Parser.parse(source: code)
		let names = FunctionsDeclaredInBodies(viewMode: .sourceAccurate).names(in: file)
		return ParameterEraser(functionNames: names).rewrite(file).description
	}

	struct Failure: Error {
		let problems: [String]
	}

	/// A function declared directly in a body, with its tokens.
	struct Function {
		let name: String
		/// The function's text with each name of a function of its body spelled as one mark, own name included.
		let abstractedText: String
		/// The names of functions of its body it spells, in order, its own name first.
		let spelledFunctionNames: [String]
	}

	/// The name of each function of `todaysBody` in `perTypeBody`.
	static func renaming(from todaysBody: CodeBlockSyntax, to perTypeBody: CodeBlockSyntax) -> Result<[String: String], Failure> {
		let todaysFunctions = functions(of: todaysBody)
		let perTypeFunctions = functions(of: perTypeBody)
		let all = todaysFunctions + perTypeFunctions
		// The two sides name their functions independently, so a name is read on its own side only.
		func index(of name: String, isToday: Bool) -> Int? {
			if isToday {
				todaysFunctions.firstIndex { $0.name == name }
			} else {
				perTypeFunctions.firstIndex { $0.name == name }.map { $0 + todaysFunctions.count }
			}
		}
		var classes = [Int]()
		var textClasses = [String: Int]()
		for function in all {
			let id = textClasses[function.abstractedText] ?? textClasses.count
			textClasses[function.abstractedText] = id
			classes.append(id)
		}
		var classCount = textClasses.count
		while true {
			var refinedClasses = [[Int]: Int]()
			var next = [Int]()
			for (position, function) in all.enumerated() {
				let isToday = position < todaysFunctions.count
				var key = [classes[position]]
				for name in function.spelledFunctionNames {
					key.append(index(of: name, isToday: isToday).map { classes[$0] } ?? -1)
				}
				let id = refinedClasses[key] ?? refinedClasses.count
				refinedClasses[key] = id
				next.append(id)
			}
			classes = next
			guard refinedClasses.count != classCount else { break }
			classCount = refinedClasses.count
		}
		var todaysByClass = [Int: [Int]]()
		var perTypeByClass = [Int: [Int]]()
		for position in all.indices {
			if position < todaysFunctions.count {
				todaysByClass[classes[position], default: []].append(position)
			} else {
				perTypeByClass[classes[position], default: []].append(position - todaysFunctions.count)
			}
		}
		var problems = [String]()
		var renaming = [String: String]()
		for id in Set(classes).sorted() {
			let todays = todaysByClass[id] ?? []
			let perTypes = perTypeByClass[id] ?? []
			if perTypes.isEmpty {
				problems.append("today’s \(todays.map { todaysFunctions[$0].name }.joined(separator: ", ")) has no function of the per-type code")
			} else if todays.isEmpty {
				problems.append("the per-type code’s \(perTypes.map { perTypeFunctions[$0].name }.joined(separator: ", ")) stands for no function of today’s")
			} else if perTypes.count == 1 {
				for today in todays {
					renaming[todaysFunctions[today].name] = perTypeFunctions[perTypes[0]].name
				}
			} else if perTypes.count == todays.count {
				for (today, perType) in zip(todays, perTypes) {
					renaming[todaysFunctions[today].name] = perTypeFunctions[perType].name
				}
			} else {
				problems.append("today’s \(todays.map { todaysFunctions[$0].name }.joined(separator: ", ")) are alike, as are the per-type code’s \(perTypes.map { perTypeFunctions[$0].name }.joined(separator: ", ")), and no pairing is one to one")
			}
		}
		guard problems.isEmpty else { return .failure(Failure(problems: problems)) }
		return .success(renaming)
	}

	/// The functions declared directly in `body`, in declaration order.
	static func functions(of body: CodeBlockSyntax) -> [Function] {
		let declarations = body.statements.compactMap { $0.item.as(FunctionDeclSyntax.self) }
		let names = Set(declarations.map(\.name.text))
		return declarations.map { declaration in
			var abstractedText = ""
			var spelledFunctionNames = [String]()
			for token in declaration.tokens(viewMode: .sourceAccurate) {
				if case let .identifier(name) = token.tokenKind, names.contains(name) {
					spelledFunctionNames.append(name)
					abstractedText += token.leadingTrivia.description + "\u{0}" + token.trailingTrivia.description
				} else {
					abstractedText += token.description
				}
			}
			// The leading trivia of the declaration is where it sits, not what it is.
			return Function(
				name: declaration.name.text,
				abstractedText: String(abstractedText.drop { $0.isWhitespace }),
				spelledFunctionNames: spelledFunctionNames,
			)
		}
	}

	/// The first line of `mapped` and `perTypeCode` that differs, numbered from 1.
	static func firstDifference(mapped: String, perTypeCode: String) -> String {
		let mappedLines = mapped.split(separator: "\n", omittingEmptySubsequences: false)
		let perTypeLines = perTypeCode.split(separator: "\n", omittingEmptySubsequences: false)
		for (index, (mappedLine, perTypeLine)) in zip(mappedLines, perTypeLines).enumerated() where mappedLine != perTypeLine {
			return "line \(index + 1) differs outside the mapping: today’s, mapped, is `\(mappedLine)`, the per-type code’s is `\(perTypeLine)`"
		}
		return "today’s code, mapped, has \(mappedLines.count) lines, the per-type code \(perTypeLines.count)"
	}

	/// The bodies of initializers and functions that no other body holds, in source order.
	final class OutermostBodies: SyntaxVisitor {
		private var found = [CodeBlockSyntax]()

		func bodies(in file: SourceFileSyntax) -> [CodeBlockSyntax] {
			walk(file)
			return found
		}

		override func visit(_ node: CodeBlockSyntax) -> SyntaxVisitorContinueKind {
			found.append(node)
			return .skipChildren
		}
	}

	/// Today's code with each outermost body's functions renamed, and each declaration of a name its body declared before
	/// dropped.
	final class MappingRewriter: SyntaxRewriter {
		private let renamings: [[String: String]]
		private var nextBody = 0

		init(renamings: [[String: String]]) {
			self.renamings = renamings
			super.init(viewMode: .sourceAccurate)
		}

		override func visit(_ node: CodeBlockSyntax) -> CodeBlockSyntax {
			let renaming = renamings[nextBody]
			nextBody += 1
			let renamed = NameRewriter(renaming: renaming).rewrite(node).cast(CodeBlockSyntax.self)
			var declared = Set<String>()
			let kept = renamed.statements.filter { item in
				guard let function = item.item.as(FunctionDeclSyntax.self) else { return true }
				return declared.insert(function.name.text).inserted
			}
			return renamed.with(\.statements, CodeBlockItemListSyntax(kept))
		}
	}

	/// A body with every identifier `renaming` names spelled as it maps it.
	final class NameRewriter: SyntaxRewriter {
		private let renaming: [String: String]

		init(renaming: [String: String]) {
			self.renaming = renaming
			super.init(viewMode: .sourceAccurate)
		}

		override func visit(_ token: TokenSyntax) -> TokenSyntax {
			guard case let .identifier(name) = token.tokenKind, let renamed = renaming[name] else { return token }
			return token.with(\.tokenKind, .identifier(renamed))
		}
	}

	/// The names of the functions declared in a body of a file, at any depth.
	final class FunctionsDeclaredInBodies: SyntaxVisitor {
		private var found = Set<String>()

		func names(in file: SourceFileSyntax) -> Set<String> {
			walk(file)
			return found
		}

		override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
			if node.parent?.is(CodeBlockItemSyntax.self) == true {
				found.insert(node.name.text)
			}
			return .visitChildren
		}
	}

	/// A file whose functions `functionNames` names take no parameters and are called with no arguments, and whose
	/// wrappers made of a closure that only calls one of them are made of the function itself.
	final class ParameterEraser: SyntaxRewriter {
		private let functionNames: Set<String>

		init(functionNames: Set<String>) {
			self.functionNames = functionNames
			super.init(viewMode: .sourceAccurate)
		}

		override func visit(_ node: FunctionDeclSyntax) -> DeclSyntax {
			let visited = super.visit(node)
			guard let function = visited.as(FunctionDeclSyntax.self), functionNames.contains(function.name.text) else { return visited }
			return DeclSyntax(function.with(\.signature.parameterClause.parameters, []))
		}

		override func visit(_ node: FunctionCallExprSyntax) -> ExprSyntax {
			let visited = super.visit(node)
			guard let call = visited.as(FunctionCallExprSyntax.self) else { return visited }
			if calledFunctionName(of: call) != nil {
				return ExprSyntax(call
					.with(\.leftParen, call.leftParen ?? .leftParenToken())
					.with(\.arguments, [])
					.with(\.rightParen, call.rightParen ?? .rightParenToken())
					.with(\.trailingClosure, nil)
					.with(\.additionalTrailingClosures, []))
			} else if call.arguments.isEmpty,
			          let closure = call.trailingClosure,
			          closure.signature == nil,
			          closure.statements.count == 1,
			          let inner = closure.statements.first?.item.as(FunctionCallExprSyntax.self),
			          let name = calledFunctionName(of: inner)
			{
				return ExprSyntax(call
					.with(\.calledExpression, call.calledExpression.with(\.trailingTrivia, []))
					.with(\.leftParen, .leftParenToken())
					.with(\.arguments, [LabeledExprSyntax(expression: DeclReferenceExprSyntax(baseName: .identifier(name)))])
					.with(\.rightParen, .rightParenToken())
					.with(\.trailingClosure, nil)
					.with(\.trailingTrivia, call.trailingTrivia))
			} else {
				return visited
			}
		}

		/// The name of the function of the file's bodies `call` calls, `nil` where it calls none.
		private func calledFunctionName(of call: FunctionCallExprSyntax) -> String? {
			guard let reference = call.calledExpression.as(DeclReferenceExprSyntax.self), functionNames.contains(reference.baseName.text) else { return nil }
			return reference.baseName.text
		}
	}
}
