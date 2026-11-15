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

// SPIKE: one generated function per type in production dependency trees.
//
// The per-path tree is built, validated and emitted exactly as before. This pass then reads the emitted body of a
// root's `init()` as Swift (SwiftParser), and shares each builder function that two or more places emit with equal
// keys: one function, placed in the innermost body every call passes through, just before the first statement that
// reaches it. The key is the function's text with its own name abstracted, so it holds the concrete type, the
// outcome of every read (a name, its `.instance`, or `nil`), and the forms received. Each label the function reads
// from outside it is captured when every place resolves it to one declaration, and is otherwise a parameter the call
// passes by name, which Swift resolves at the call to the declaration the place's function read. Nothing is merged
// whose reads would resolve elsewhere: every condition that cannot be proven sends the group back to per-path text
// ("not shared"), and a body in which no key has two places is returned unchanged, byte for byte.
//
// `SAFEDI_PER_PATH_EMISSION=1` turns the pass off. `SAFEDI_SPIKE_STATS_FILE` names a file each root appends one JSON
// line of statistics to.

import Foundation
import SwiftParser
import SwiftSyntax

public enum PerTypeEmission {
	static var isEnabled: Bool {
		ProcessInfo.processInfo.environment["SAFEDI_PER_PATH_EMISSION"] != "1"
	}

	/// Statistics of one root's pass.
	struct Statistics: Codable {
		var rootType = ""
		var linesBefore = 0
		var linesAfter = 0
		var iterations = 0
		/// Groups shared, and the places they replaced.
		var sharedGroups = 0
		var sharedPlaces = 0
		/// Groups of two or more places with one key that were not shared, by reason.
		var notSharedByReason = [String: Int]()
		/// Places in groups not shared.
		var notSharedPlaces = 0
		/// Types that the root's per-path text builds in two or more builder functions, before and after.
		var typesWithTwoOrMoreFunctionsBefore = 0
		var typesWithTwoOrMoreFunctionsAfter = 0
		var skippedReason: String?
		/// Types whose remaining builder functions differ only where one reads `nil` and another a name: the places the
		/// brief's key (which leaves out whether a declaration exists) would share and this pass's text key does not.
		var typesSplitOnlyByNil = 0
		var placesSplitOnlyByNil = 0
		/// Sets of groups that call one another around a cycle, shared at once, with their groups and places.
		var cyclicComponents = 0
		var cyclicGroups = 0
		var cyclicPlaces = 0
	}

	/// A generated file with the body of every root's `init()` shared per type, as the emitter shares it: for a test that
	/// compares the two emitters on output generated once, per path. A seam's initializers take parameters, so no seam
	/// body is touched.
	public static func transformGeneratedFile(_ file: String) -> String {
		var lines = file.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
		var index = 0
		while index < lines.count {
			let line = lines[index]
			guard line.hasPrefix("    "), line.hasSuffix("init() {"), line.contains("public "),
			      let end = lines[(index + 1)...].firstIndex(where: { $0.hasPrefix("        self.init(") }),
			      end > index + 1
			else {
				index += 1
				continue
			}
			let body = lines[(index + 1)..<end].joined(separator: "\n")
			let transformed = transform(body: body, rootType: "")
			lines.replaceSubrange((index + 1)..<end, with: transformed.split(separator: "\n", omittingEmptySubsequences: false).map(String.init))
			index += 1
		}
		return lines.joined(separator: "\n")
	}

	/// The body of a root's `init()` (the lines before `self.init`), shared per type.
	static func transform(body: String, rootType: String) -> String {
		var statistics = Statistics()
		statistics.rootType = rootType
		statistics.linesBefore = body.split(separator: "\n").count
		defer {
			record(statistics)
		}
		// The parser limits nesting, and this pass recurses per level of the syntax tree: a deep chain stays per path.
		let maximumIndentation = body.split(separator: "\n").lazy.map { $0.prefix(while: { $0 == " " }).count }.max() ?? 0
		guard maximumIndentation / 4 <= 48 else {
			statistics.skippedReason = "deeper than 48 levels"
			statistics.linesAfter = statistics.linesBefore
			return body
		}
		var text = body
		var first = true
		while true {
			guard let pass = Pass(body: text) else {
				statistics.skippedReason = first ? "does not parse" : "a pass produced text that does not parse"
				statistics.linesAfter = statistics.linesBefore
				return body
			}
			if first {
				statistics.typesWithTwoOrMoreFunctionsBefore = pass.typesWithTwoOrMoreFunctions
				first = false
			}
			// Failures count only once nothing more is shared: a cycle's component can clear them.
			var passStatistics = statistics
			let next: String
			if let shared = pass.shareInnermostGroups(statistics: &passStatistics) {
				statistics = passStatistics
				next = shared
			} else if let shared = pass.shareCyclicComponent(statistics: &statistics) {
				next = shared
			} else {
				statistics = passStatistics
				statistics.typesWithTwoOrMoreFunctionsAfter = pass.typesWithTwoOrMoreFunctions
				pass.countSplitOnlyByNil(statistics: &statistics)
				break
			}
			statistics.iterations += 1
			text = next
		}
		statistics.linesAfter = text.split(separator: "\n").count
		return text
	}

	private static func record(_ statistics: Statistics) {
		guard let path = ProcessInfo.processInfo.environment["SAFEDI_SPIKE_STATS_FILE"],
		      let data = try? JSONEncoder().encode(statistics)
		else { return }
		let line = data + Data("\n".utf8)
		let descriptor = open(path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
		guard descriptor >= 0 else { return }
		_ = line.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
		close(descriptor)
	}

	// MARK: - One pass over the text

	private static let wrapperName = "__safeDI_spikeWrapper"
	private static let wrapperPrefix = "func \(wrapperName)() {\n"
	private static let wrapperSuffix = "\n}\n"

	private struct Declaration {
		enum Kind {
			case value
			case parameter
			case function
		}

		let name: String
		let offset: Int
		let kind: Kind
		let typeText: String?
		let scope: Int
		/// For a function: its index among `functions`.
		var function: Int?
	}

	private struct Scope {
		let parent: Int?
		/// The function whose body this is, if any.
		let function: Int?
		/// Whether code here runs inside a `@Sendable` function or a closure a `Sendable` wrapper is made from.
		let isSendableBoundary: Bool
		/// The start of the statement in the parent scope that holds this scope.
		var names = [String: Int]()
		/// The range of the scope's syntax.
		let range: Range<Int>
	}

	private struct Reference {
		let name: String
		let offset: Int
		let length: Int
		let scope: Int
		let declaration: Int?
		/// Set when the reference is the called expression of a call: the offset of its right parenthesis, and whether it
		/// passes arguments.
		let callRightParen: Int?
		let callHasArguments: Bool
		/// For a reference passed as an argument: the called expression's text.
		let argumentOfCallee: String?
		/// For a reference that is a labeled argument's whole expression: the label.
		let argumentLabel: String?
	}

	/// A `label: nil` argument.
	private struct NilArgument {
		let label: String
		let offset: Int
		let scope: Int
	}

	private struct Function {
		let name: String
		let declaration: Int
		let syntax: FunctionDeclSyntax
		let scope: Int
		let bodyScope: Int
		/// The range of the declaration's lines, newline included.
		let lineRange: Range<Int>
		let headerRange: Range<Int>
		let nameRange: Range<Int>
		let indentation: String
		let isSendable: Bool
		let returnType: String
		let parametersText: String
		let parameterNames: [String]
		/// The statement of the enclosing scope this declaration is.
		let statementIndex: Int
	}

	private final class Pass {
		let source: [UInt8]
		let bodyStart: Int
		let bodyEnd: Int
		var declarations = [Declaration]()
		var scopes = [Scope]()
		var references = [Reference]()
		var functions = [Function]()
		/// The top-level statements of each scope: their start offsets (line starts) in order.
		var statementLineStartsByScope = [Int: [Int]]()
		var statementRangesByScope = [Int: [Range<Int>]]()
		var functionIndexBySyntax = [SyntaxIdentifier: Int]()
		var allIdentifiers = Set<String>()
		var unsupportedScopes = Set<Int>()
		var nilArguments = [NilArgument]()
		lazy var referencesByDeclaration: [Int: [Int]] = {
			var result = [Int: [Int]]()
			for (index, reference) in references.enumerated() {
				if let declaration = reference.declaration {
					result[declaration, default: []].append(index)
				}
			}
			return result
		}()

		init?(body: String) {
			let wrapped = PerTypeEmission.wrapperPrefix + body + PerTypeEmission.wrapperSuffix
			source = Array(wrapped.utf8)
			bodyStart = PerTypeEmission.wrapperPrefix.utf8.count
			bodyEnd = bodyStart + body.utf8.count
			let file = Parser.parse(source: wrapped)
			guard !file.hasError,
			      let wrapper = file.statements.first?.item.as(FunctionDeclSyntax.self),
			      let statements = wrapper.body?.statements
			else { return nil }
			let rootScope = addScope(parent: nil, function: nil, isSendableBoundary: false, range: bodyStart..<bodyEnd)
			visitBlock(statements, scope: rootScope)
		}

		// MARK: Reading

		private func addScope(parent: Int?, function: Int?, isSendableBoundary: Bool, range: Range<Int>) -> Int {
			scopes.append(Scope(parent: parent, function: function, isSendableBoundary: isSendableBoundary, range: range))
			return scopes.count - 1
		}

		private func lineStart(of offset: Int) -> Int {
			var index = offset
			while index > 0, source[index - 1] != UInt8(ascii: "\n") {
				index -= 1
			}
			return index
		}

		private func lineEnd(after offset: Int) -> Int {
			var index = offset
			while index < source.count, source[index] != UInt8(ascii: "\n") {
				index += 1
			}
			return min(index + 1, source.count)
		}

		func text(_ range: Range<Int>) -> String {
			String(decoding: source[range], as: UTF8.self)
		}

		private func declare(_ name: String, offset: Int, kind: Declaration.Kind, typeText: String?, scope: Int) -> Int {
			declarations.append(Declaration(name: name, offset: offset, kind: kind, typeText: typeText, scope: scope))
			scopes[scope].names[name] = declarations.count - 1
			allIdentifiers.insert(name)
			return declarations.count - 1
		}

		private func resolve(_ name: String, from scope: Int) -> Int? {
			var current: Int? = scope
			while let index = current {
				if let declaration = scopes[index].names[name] {
					return declaration
				}
				current = scopes[index].parent
			}
			return nil
		}

		private func visitBlock(_ statements: CodeBlockItemListSyntax, scope: Int) {
			// A local function is in scope throughout its block.
			var lineStarts = [Int]()
			var ranges = [Range<Int>]()
			for (statementIndex, item) in statements.enumerated() {
				let start = item.positionAfterSkippingLeadingTrivia.utf8Offset
				lineStarts.append(lineStart(of: start))
				ranges.append(lineStart(of: start)..<item.endPositionBeforeTrailingTrivia.utf8Offset)
				if let function = item.item.as(FunctionDeclSyntax.self) {
					registerFunction(function, scope: scope, statementIndex: statementIndex)
				}
			}
			statementLineStartsByScope[scope] = lineStarts
			statementRangesByScope[scope] = ranges
			for item in statements {
				visit(Syntax(item), scope: scope)
			}
		}

		private func registerFunction(_ function: FunctionDeclSyntax, scope: Int, statementIndex: Int) {
			let name = function.name.text
			let declarationIndex = declare(name, offset: function.name.positionAfterSkippingLeadingTrivia.utf8Offset, kind: .function, typeText: nil, scope: scope)
			let firstToken = function.positionAfterSkippingLeadingTrivia.utf8Offset
			let start = lineStart(of: firstToken)
			let end = lineEnd(after: function.endPositionBeforeTrailingTrivia.utf8Offset - 1)
			let bodyOpen = function.body?.leftBrace.positionAfterSkippingLeadingTrivia.utf8Offset ?? firstToken
			let isSendable = function.attributes.contains(where: { $0.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "Sendable" })
			let parameters = function.signature.parameterClause.parameters
			let functionIndex = functions.count
			functions.append(Function(
				name: name,
				declaration: declarationIndex,
				syntax: function,
				scope: scope,
				bodyScope: -1,
				lineRange: start..<end,
				headerRange: firstToken..<bodyOpen,
				nameRange: function.name.positionAfterSkippingLeadingTrivia.utf8Offset..<function.name.endPositionBeforeTrailingTrivia.utf8Offset,
				indentation: text(start..<firstToken),
				isSendable: isSendable,
				returnType: function.signature.returnClause?.type.trimmedDescription ?? "",
				parametersText: parameters.trimmedDescription,
				parameterNames: parameters.map { ($0.secondName ?? $0.firstName).text },
				statementIndex: statementIndex,
			))
			declarations[declarationIndex].function = functionIndex
			functionIndexBySyntax[function.id] = functionIndex
		}

		private func visit(_ node: Syntax, scope: Int) {
			if let function = node.as(FunctionDeclSyntax.self) {
				guard let functionIndex = functionIndexBySyntax[function.id], let body = function.body else {
					unsupportedScopes.insert(scope)
					return
				}
				let bodyScope = addScope(
					parent: scope,
					function: functionIndex,
					isSendableBoundary: functions[functionIndex].isSendable,
					range: body.positionAfterSkippingLeadingTrivia.utf8Offset..<body.endPositionBeforeTrailingTrivia.utf8Offset,
				)
				let old = functions[functionIndex]
				functions[functionIndex] = Function(
					name: old.name, declaration: old.declaration, syntax: old.syntax, scope: old.scope, bodyScope: bodyScope,
					lineRange: old.lineRange, headerRange: old.headerRange, nameRange: old.nameRange, indentation: old.indentation,
					isSendable: old.isSendable, returnType: old.returnType, parametersText: old.parametersText,
					parameterNames: old.parameterNames, statementIndex: old.statementIndex,
				)
				for parameter in function.signature.parameterClause.parameters {
					let name = (parameter.secondName ?? parameter.firstName)
					_ = declare(name.text, offset: name.positionAfterSkippingLeadingTrivia.utf8Offset, kind: .parameter, typeText: parameter.type.trimmedDescription, scope: bodyScope)
				}
				visitBlock(body.statements, scope: bodyScope)
				return
			}
			if let closure = node.as(ClosureExprSyntax.self) {
				var isSendable = false
				if let call = closure.parent?.as(FunctionCallExprSyntax.self) ?? closure.parent?.parent?.parent?.as(FunctionCallExprSyntax.self) {
					isSendable = PerTypeEmission.isSendableWrapper(call.calledExpression.trimmedDescription)
				}
				if closure.signature != nil {
					unsupportedScopes.insert(scope)
				}
				let closureScope = addScope(
					parent: scope,
					function: nil,
					isSendableBoundary: isSendable,
					range: closure.positionAfterSkippingLeadingTrivia.utf8Offset..<closure.endPositionBeforeTrailingTrivia.utf8Offset,
				)
				visitBlock(closure.statements, scope: closureScope)
				return
			}
			if let variable = node.as(VariableDeclSyntax.self) {
				for binding in variable.bindings {
					if let initializer = binding.initializer {
						visit(Syntax(initializer.value), scope: scope)
					}
				}
				for binding in variable.bindings {
					guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else {
						unsupportedScopes.insert(scope)
						continue
					}
					let typeText = binding.typeAnnotation?.type.trimmedDescription ?? binding.initializer.flatMap { PerTypeEmission.inferredType(of: $0.value) }
					_ = declare(pattern.identifier.text, offset: pattern.positionAfterSkippingLeadingTrivia.utf8Offset, kind: .value, typeText: typeText, scope: scope)
				}
				return
			}
			if let argument = node.as(LabeledExprSyntax.self), argument.expression.is(NilLiteralExprSyntax.self), let label = argument.label {
				nilArguments.append(NilArgument(label: label.text, offset: argument.expression.positionAfterSkippingLeadingTrivia.utf8Offset, scope: scope))
			}
			if node.is(SwitchExprSyntax.self) || node.is(IfExprSyntax.self) || node.is(GuardStmtSyntax.self) || node.is(ForStmtSyntax.self) {
				unsupportedScopes.insert(scope)
			}
			if let reference = node.as(DeclReferenceExprSyntax.self) {
				let name = reference.baseName.text
				allIdentifiers.insert(name)
				var callRightParen: Int?
				var callHasArguments = false
				var argumentOfCallee: String?
				if let call = reference.parent?.as(FunctionCallExprSyntax.self), call.calledExpression.id == reference.id {
					callRightParen = call.rightParen?.positionAfterSkippingLeadingTrivia.utf8Offset
					callHasArguments = !call.arguments.isEmpty
				} else if let call = reference.parent?.parent?.parent?.as(FunctionCallExprSyntax.self) {
					argumentOfCallee = call.calledExpression.trimmedDescription
				}
				let labeledArgument = reference.parent?.as(LabeledExprSyntax.self)
				references.append(Reference(
					name: name,
					offset: reference.positionAfterSkippingLeadingTrivia.utf8Offset,
					length: reference.baseName.endPositionBeforeTrailingTrivia.utf8Offset - reference.positionAfterSkippingLeadingTrivia.utf8Offset,
					scope: scope,
					declaration: resolve(name, from: scope),
					callRightParen: callRightParen,
					callHasArguments: callHasArguments,
					argumentOfCallee: argumentOfCallee,
					argumentLabel: labeledArgument?.expression.id == reference.id ? labeledArgument?.label?.text : nil,
				))
				return
			}
			for child in node.children(viewMode: .sourceAccurate) {
				visit(child, scope: scope)
			}
		}

		// MARK: Structure

		private func isAncestorOrSelf(_ ancestor: Int, of scope: Int) -> Bool {
			var current: Int? = scope
			while let index = current {
				if index == ancestor { return true }
				current = scopes[index].parent
			}
			return false
		}

		private func chain(of scope: Int) -> [Int] {
			var result = [Int]()
			var current: Int? = scope
			while let index = current {
				result.append(index)
				current = scopes[index].parent
			}
			return result.reversed()
		}

		/// Whether `offset` lies inside function `function`'s declaration.
		private func isInside(_ offset: Int, function: Int) -> Bool {
			functions[function].lineRange.contains(offset)
		}

		var candidateFunctions: [Int] {
			functions.indices.filter { functions[$0].name.hasPrefix("__safeDI_") && functions[$0].name != PerTypeEmission.wrapperName }
		}

		/// Types the text builds in two or more builder functions.
		var typesWithTwoOrMoreFunctions: Int {
			var counts = [String: Int]()
			for index in candidateFunctions {
				counts[functions[index].returnType, default: 0] += 1
			}
			return counts.values.count(where: { $0 > 1 })
		}

		/// Counts the types whose remaining builder functions have keys that differ only by `nil` against a name.
		func countSplitOnlyByNil(statistics: inout Statistics) {
			var keysByType = [String: [String]]()
			for function in candidateFunctions {
				keysByType[functions[function].returnType, default: []].append(key(of: function))
			}
			func tokens(_ text: String) -> [Substring] {
				var result = [Substring]()
				var start = text.startIndex
				var index = text.startIndex
				while index < text.endIndex {
					let character = text[index]
					if !(character.isLetter || character.isNumber || character == "_") {
						if start < index { result.append(text[start..<index]) }
						result.append(text[index...index])
						start = text.index(after: index)
					}
					index = text.index(after: index)
				}
				if start < text.endIndex { result.append(text[start...]) }
				return result
			}
			for type in keysByType.keys.sorted() {
				let keys = keysByType[type, default: []]
				let distinct = Array(Set(keys)).sorted()
				guard distinct.count > 1 else { continue }
				let tokenized = distinct.map(tokens)
				var places = Set<Int>()
				for i in tokenized.indices {
					for j in tokenized.indices where j > i && tokenized[i].count == tokenized[j].count {
						let differing = zip(tokenized[i], tokenized[j]).filter { $0 != $1 }
						if !differing.isEmpty, differing.allSatisfy({ ($0 == "nil") != ($1 == "nil") }) {
							places.insert(i)
							places.insert(j)
						}
					}
				}
				if !places.isEmpty {
					statistics.typesSplitOnlyByNil += 1
					statistics.placesSplitOnlyByNil += keys.count(where: { key in places.contains(where: { distinct[$0] == key }) })
				}
			}
		}

		/// The key of a function: its declaration's text, its indentation removed, its own name and `@Sendable` abstracted.
		private func key(of function: Int) -> String {
			let declaration = functions[function]
			var bytes = [UInt8]()
			var index = declaration.lineRange.lowerBound
			let ownReferences = referencesByDeclaration[declaration.declaration, default: []].map { references[$0].offset }.filter { declaration.lineRange.contains($0) }
			var ownReferenceIndex = 0
			let replaced = ([declaration.nameRange.lowerBound] + ownReferences).sorted()
			while index < declaration.lineRange.upperBound {
				if ownReferenceIndex < replaced.count, index == replaced[ownReferenceIndex] {
					bytes += Array("@SELF@".utf8)
					index += declaration.name.utf8.count
					ownReferenceIndex += 1
					continue
				}
				bytes.append(source[index])
				index += 1
			}
			var text = String(decoding: bytes, as: UTF8.self)
			text = text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
				line.hasPrefix(declaration.indentation) ? String(line.dropFirst(declaration.indentation.count)) : String(line)
			}.joined(separator: "\n")
			if text.hasPrefix("@Sendable ") {
				text.removeFirst("@Sendable ".count)
			}
			return text
		}

		private struct Group {
			var members: [Int]
		}

		private struct Plan {
			var members: [Int]
			var newName: String
			var isSendable: Bool
			/// Labels passed as parameters, in the order the body first reads them, with their types.
			var parameters: [(name: String, type: String)]
			var placementScope: Int
			var anchorLineStart: Int
			var anchorIndentation: String
			var firstSiteOffset: Int
		}

		/// Shares the groups no other group's member holds; `nil` when nothing is shared.
		func shareInnermostGroups(statistics: inout Statistics) -> String? {
			var membersByKey = [String: [Int]]()
			var keyOrder = [String]()
			for function in candidateFunctions {
				let key = key(of: function)
				if membersByKey[key] == nil {
					keyOrder.append(key)
				}
				membersByKey[key, default: []].append(function)
			}
			let groups = keyOrder.compactMap { membersByKey[$0] }.filter { $0.count > 1 }
			guard !groups.isEmpty else { return nil }
			let memberOfGroup = Dictionary(groups.enumerated().flatMap { index, members in members.map { ($0, index) } }, uniquingKeysWith: { first, _ in first })
			var plans = [Plan]()
			var failures = [(reason: String, places: Int)]()
			for (groupIndex, members) in groups.enumerated() {
				// Another group's member inside a member waits for that group.
				let holdsAnotherGroup = members.contains { member in
					functions.indices.contains { other in
						other != member && memberOfGroup[other] != nil && memberOfGroup[other] != groupIndex
							&& functions[member].lineRange.contains(functions[other].lineRange.lowerBound)
					}
				}
				if holdsAnotherGroup {
					failures.append(("holds a group that is not shared", members.count))
					continue
				}
				switch plan(of: members, groupOf: memberOfGroup, groupIndex: groupIndex) {
				case let .success(plan):
					plans.append(plan)
				case let .failure(reason):
					failures.append((reason.reason, members.count))
				}
			}
			guard !plans.isEmpty else {
				for failure in failures {
					statistics.notSharedByReason[failure.reason, default: 0] += 1
					statistics.notSharedPlaces += failure.places
				}
				return nil
			}
			// Failures are recorded only when the pass ends, since a failure can clear once an inner group is shared.
			for plan in plans {
				statistics.sharedGroups += 1
				statistics.sharedPlaces += plan.members.count
			}
			return apply(plans)
		}

		private struct Failure: Error {
			let reason: String
		}

		private func plan(of members: [Int], groupOf memberOfGroup: [Int: Int], groupIndex: Int) -> Result<Plan, Failure> {
			// Members whose bodies the reader could not model stay per path.
			for member in members {
				let bodyScope = functions[member].bodyScope
				if unsupportedScopes.contains(where: { isAncestorOrSelf(bodyScope, of: $0) }) {
					return .failure(Failure(reason: "body holds a statement the pass does not model (switch, if, guard, a closure's parameters)"))
				}
				if functions[member].parameterNames.contains(where: { $0.hasPrefix("scope") || $0.hasPrefix("__safeDI_") }) {
					return .failure(Failure(reason: "a seam's fill"))
				}
				if text(functions[member].lineRange).contains("_ = ") {
					return .failure(Failure(reason: "subtree holds a seam call"))
				}
			}
			// Each member's reads from outside it.
			var readsByMember = [[(name: String, declaration: Int?, offset: Int)]]()
			for member in members {
				let range = functions[member].lineRange
				var reads = [(name: String, declaration: Int?, offset: Int)]()
				for reference in references where range.contains(reference.offset) {
					guard let declaration = reference.declaration else { continue }
					if declaration == functions[member].declaration { continue }
					if range.contains(declarations[declaration].offset) { continue }
					reads.append((reference.name, declaration, reference.offset))
				}
				readsByMember.append(reads)
			}
			// The labels read, in the order the first member's body first reads them.
			var labels = [String]()
			for read in readsByMember[0] where !labels.contains(read.name) {
				labels.append(read.name)
			}
			for reads in readsByMember.dropFirst() where Set(reads.map(\.name)) != Set(labels) {
				return .failure(Failure(reason: "members read different labels"))
			}
			// Sites: references to each member outside it.
			var sites = [Reference]()
			var recursiveSites = [Reference]()
			for member in members {
				for reference in references where reference.declaration == functions[member].declaration {
					if functions[member].lineRange.contains(reference.offset) {
						if member == members[0] {
							recursiveSites.append(reference)
						}
					} else {
						sites.append(reference)
					}
				}
			}
			guard !sites.isEmpty else { return .failure(Failure(reason: "a member is never called")) }
			// A member referred to in any other way than a call or as a wrapper's argument stays per path.
			for site in sites + recursiveSites where site.callRightParen == nil && site.argumentOfCallee == nil {
				return .failure(Failure(reason: "a member is referred to other than by a call or a wrapper"))
			}
			// The placement: the innermost scope that encloses every site.
			let siteChains = sites.map { chain(of: $0.scope) }
			var placement = siteChains[0]
			for siteChain in siteChains.dropFirst() {
				placement = Array(zip(placement, siteChain).prefix(while: { $0 == $1 }).map(\.0))
			}
			guard var placementScope = placement.last else { return .failure(Failure(reason: "no common scope")) }
			// A closure's body holds no declaration: place the function in the body that holds the closure.
			while scopes[placementScope].function == nil, let parent = scopes[placementScope].parent {
				placementScope = parent
			}
			for member in members where isAncestorOrSelf(functions[member].bodyScope, of: placementScope) {
				return .failure(Failure(reason: "placement inside a member"))
			}
			// `@Sendable` when a member was, or a site reaches it from a `@Sendable` function or wrapper closure inside the placement.
			var isSendable = members.contains { functions[$0].isSendable }
			for site in sites {
				if let callee = site.argumentOfCallee, PerTypeEmission.isSendableWrapper(callee) {
					isSendable = true
				}
				for scope in chain(of: site.scope).drop(while: { $0 != placementScope }).dropFirst() where scopes[scope].isSendableBoundary {
					isSendable = true
				}
			}
			// Captured or passed, per label.
			var parameters = [(name: String, type: String)]()
			for label in labels {
				let declarationsOfLabel = readsByMember.map { reads in reads.first(where: { $0.name == label })?.declaration }
				guard let firstDeclaration = declarationsOfLabel[0], declarationsOfLabel.allSatisfy({ $0 != nil }) else {
					return .failure(Failure(reason: "a read resolves to nothing"))
				}
				let resolved = declarationsOfLabel.compactMap(\.self)
				if declarations[firstDeclaration].kind == .function {
					// A function read from outside: the same function at every place, visible at the placement, and
					// `@Sendable` where the shared function is.
					guard resolved.allSatisfy({ $0 == firstDeclaration }) else {
						return .failure(Failure(reason: "members call different enclosing functions (a cycle or a loop of builders)"))
					}
					guard let calledFunction = declarations[firstDeclaration].function,
					      isAncestorOrSelf(declarations[firstDeclaration].scope, of: placementScope)
					      || isAncestorOrSelf(functions[calledFunction].bodyScope, of: placementScope)
					else {
						return .failure(Failure(reason: "an enclosing function is not visible at the placement"))
					}
					if memberOfGroup[calledFunction] != nil {
						return .failure(Failure(reason: "calls a member of another group (waits a pass)"))
					}
					if isSendable, !functions[calledFunction].isSendable {
						return .failure(Failure(reason: "a @Sendable function would call one that is not"))
					}
					continue
				}
				let declarationScope = declarations[firstDeclaration].scope
				let isSameEverywhere = resolved.allSatisfy { $0 == firstDeclaration }
				let isVisibleAtPlacement = isAncestorOrSelf(declarationScope, of: placementScope)
					&& !chain(of: placementScope).drop(while: { $0 != declarationScope }).dropFirst().contains(where: { scopes[$0].names[label] != nil })
				if isSameEverywhere, isVisibleAtPlacement, !isSendable {
					continue
				}
				let types = resolved.map { declarations[$0].typeText }
				guard let type = types[0], types.allSatisfy({ $0 == type }) else {
					return .failure(Failure(reason: types.contains(nil) ? "a declaration read has no spelled type" : "declarations read have different types"))
				}
				let parameterType = type.contains("->") && !type.hasSuffix("?") && !type.contains("@escaping") ? "@escaping \(type)" : type
				parameters.append((label, parameterType))
			}
			// At each site, a passed label must resolve to what the member it calls read; in a recursive call, to the parameter.
			let memberByDeclaration = Dictionary(members.enumerated().map { (functions[$0.element].declaration, $0.offset) }, uniquingKeysWith: { first, _ in first })
			for site in sites {
				guard let declaration = site.declaration, let memberIndex = memberByDeclaration[declaration] else { continue }
				for parameter in parameters {
					let expected = readsByMember[memberIndex].first(where: { $0.name == parameter.name })?.declaration
					guard resolve(parameter.name, from: site.scope) == expected else {
						return .failure(Failure(reason: "a passed label resolves elsewhere at the call"))
					}
				}
			}
			for site in recursiveSites {
				for parameter in parameters {
					guard let declaration = resolve(parameter.name, from: site.scope),
					      declarations[declaration].scope == functions[members[0]].bodyScope
					else {
						return .failure(Failure(reason: "a recursive call's label is declared again inside"))
					}
				}
			}
			// The anchor: the placement's first statement that reaches a site.
			guard let lineStarts = statementLineStartsByScope[placementScope], let ranges = statementRangesByScope[placementScope] else {
				return .failure(Failure(reason: "placement has no statements"))
			}
			let firstSiteOffset = sites.map(\.offset).min() ?? 0
			guard let anchorIndex = ranges.firstIndex(where: { $0.contains(firstSiteOffset) || $0.lowerBound > firstSiteOffset }) else {
				return .failure(Failure(reason: "no anchor"))
			}
			// The first statement that reaches a site might be a member itself, which moves: anchor after it, to the statement
			// that follows, which reads what it built.
			var anchor = anchorIndex
			while anchor < lineStarts.count, members.contains(where: { functions[$0].lineRange.lowerBound == lineStarts[anchor] }) {
				anchor += 1
			}
			guard anchor < lineStarts.count else { return .failure(Failure(reason: "no anchor")) }
			let anchorLineStart = lineStarts[anchor]
			var indentationEnd = anchorLineStart
			while indentationEnd < source.count, source[indentationEnd] == UInt8(ascii: " ") {
				indentationEnd += 1
			}
			// The name: the members' own when they share it and nothing else declares or reads it; else made unique.
			var newName = functions[members[0]].name
			let otherFunctionsWithName = functions.indices.contains { index in functions[index].name == newName && !members.contains(index) }
			if otherFunctionsWithName || members.contains(where: { functions[$0].name != newName }) {
				repeat {
					newName += "_"
				} while allIdentifiers.contains(newName)
			}
			allIdentifiers.insert(newName)
			return .success(Plan(
				members: members,
				newName: newName,
				isSendable: isSendable,
				parameters: parameters,
				placementScope: placementScope,
				anchorLineStart: anchorLineStart,
				anchorIndentation: text(anchorLineStart..<indentationEnd),
				firstSiteOffset: firstSiteOffset,
			))
		}

		/// Shares the functions of a cycle, which `shareInnermostGroups` cannot share one group at a time: a closer calls
		/// the function of the declaration it repeats, which encloses it, so each copy holds or calls the others, and the
		/// copies' texts differ by where the cycle closes. Functions are classed by bisimulation – their text without the
		/// candidate functions they declare, then the classes of the functions each reference names, refined until stable –
		/// and every class reached from one of two or more members moves, as one function, to one block, where local
		/// functions can call one another. `nil` when there is nothing to share.
		/// The first member's parameters, each made optional where any member takes it optionally.
		func unifiedParametersText(of members: [Int]) -> String {
			let parameterLists = members.map { Array(functions[$0].syntax.signature.parameterClause.parameters) }
			guard let first = parameterLists.first else { return "" }
			var parts = [String]()
			for (index, parameter) in first.enumerated() {
				let optional = parameterLists.contains { index < $0.count && $0[index].type.is(OptionalTypeSyntax.self) }
				let type = parameter.type.is(OptionalTypeSyntax.self) || !optional ? parameter.type.trimmedDescription : "\(parameter.type.trimmedDescription)?"
				let names = [parameter.firstName.text] + (parameter.secondName.map { [$0.text] } ?? [])
				parts.append("\(names.joined(separator: " ")): \(type)")
			}
			return parts.joined(separator: ", ")
		}

		func shareCyclicComponent(statistics: inout Statistics) -> String? {
			let candidates = candidateFunctions
			let candidateSet = Set(candidates)
			// The candidate functions declared inside each candidate, directly or deeper.
			var nestedByFunction = [Int: [Int]]()
			for function in candidates {
				nestedByFunction[function] = candidates.filter { $0 != function && functions[function].lineRange.contains(functions[$0].lineRange.lowerBound) }
			}
			func isInsideNested(_ offset: Int, of function: Int) -> Bool {
				nestedByFunction[function, default: []].contains { functions[$0].lineRange.contains(offset) }
			}
			// The references in a function's own text (outside the candidates it declares), in order.
			var ownReferencesByFunction = [Int: [Reference]]()
			for function in candidates {
				let range = functions[function].lineRange
				ownReferencesByFunction[function] = references.filter { range.contains($0.offset) && !isInsideNested($0.offset, of: function) }
			}
			var ownNilArgumentsByFunction = [Int: [NilArgument]]()
			for function in candidates {
				let range = functions[function].lineRange
				ownNilArgumentsByFunction[function] = nilArguments.filter { range.contains($0.offset) && !isInsideNested($0.offset, of: function) }
			}
			func targetFunction(of reference: Reference) -> Int? {
				guard let declaration = reference.declaration, let function = declarations[declaration].function, candidateSet.contains(function) else { return nil }
				return function
			}
			// The initial key: the text without nested candidates, every candidate reference's name abstracted.
			func strippedKey(of function: Int) -> String {
				let declaration = functions[function]
				var edits = nestedByFunction[function, default: []].map { Edit.replace(functions[$0].lineRange, "") }
				for reference in ownReferencesByFunction[function, default: []] {
					if targetFunction(of: reference) != nil {
						edits.append(.replace(reference.offset..<(reference.offset + reference.length), "@F@"))
					} else if reference.argumentLabel == reference.name {
						// Whether a declaration exists is not in the key: `x: x` and `x: nil` key alike.
						edits.append(.replace(reference.offset..<(reference.offset + reference.length), "@V@"))
					}
				}
				for argument in ownNilArgumentsByFunction[function, default: []] {
					edits.append(.replace(argument.offset..<(argument.offset + 3), "@V@"))
				}
				edits.append(.replace(declaration.nameRange, "@F@"))
				// Whether a parameter is optional is not in the key: a member that takes `x: X?` runs the same text as one
				// that takes `x: X`, so the shared function takes `X?` (`unifiedParametersText`).
				for parameter in declaration.syntax.signature.parameterClause.parameters {
					guard let optional = parameter.type.as(OptionalTypeSyntax.self) else { continue }
					let start = optional.positionAfterSkippingLeadingTrivia.utf8Offset
					edits.append(.replace(start..<optional.endPositionBeforeTrailingTrivia.utf8Offset, optional.wrappedType.trimmedDescription))
				}
				var text = render(declaration.lineRange, edits: edits)
				text = text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
					line.hasPrefix(declaration.indentation) ? String(line.dropFirst(declaration.indentation.count)) : String(line)
				}.joined(separator: "\n")
				return text
			}
			var classOf = [Int: Int]()
			var classKeys = [String: Int]()
			for function in candidates {
				let key = strippedKey(of: function)
				if classKeys[key] == nil { classKeys[key] = classKeys.count }
				classOf[function] = classKeys[key]
			}
			// Refine by the classes each function's references name, until no class splits.
			while true {
				var refinedKeys = [String: Int]()
				var refined = [Int: Int]()
				for function in candidates {
					let targets = ownReferencesByFunction[function, default: []].compactMap(targetFunction).map { String(classOf[$0] ?? -1) }
					let key = "\(classOf[function] ?? -1)|" + targets.joined(separator: ",")
					if refinedKeys[key] == nil { refinedKeys[key] = refinedKeys.count }
					refined[function] = refinedKeys[key]
				}
				let stable = refinedKeys.count == Set(classOf.values).count
				classOf = refined
				if stable { break }
			}
			var membersByClass = [Int: [Int]]()
			for function in candidates {
				membersByClass[classOf[function] ?? -1, default: []].append(function)
			}
			guard membersByClass.values.contains(where: { $0.count > 1 }) else { return nil }
			func fail(_ reason: String) -> String? {
				statistics.notSharedByReason["cycle: " + reason, default: 0] += 1
				return nil
			}
			// Each member's value reads from outside it.
			// Each member's value reads from outside it, in order; a `label: nil` argument reads `label` as `nilRead`.
			let nilRead = -1
			func valueReads(of function: Int) -> [(name: String, declaration: Int)] {
				let range = functions[function].lineRange
				var reads = ownReferencesByFunction[function, default: []].compactMap { reference -> (name: String, declaration: Int, offset: Int)? in
					guard let declaration = reference.declaration, targetFunction(of: reference) == nil,
					      !range.contains(declarations[declaration].offset)
					else { return nil }
					return (reference.name, declaration, reference.offset)
				}
				reads += ownNilArgumentsByFunction[function, default: []].map { ($0.label, nilRead, $0.offset) }
				return reads.sorted { $0.offset < $1.offset }.map { ($0.name, $0.declaration) }
			}
			func valueReadOffsets(of function: Int) -> [Int] {
				let range = functions[function].lineRange
				var offsets = ownReferencesByFunction[function, default: []].compactMap { reference -> Int? in
					guard let declaration = reference.declaration, targetFunction(of: reference) == nil,
					      !range.contains(declarations[declaration].offset)
					else { return nil }
					return reference.offset
				}
				offsets += ownNilArgumentsByFunction[function, default: []].map(\.offset)
				return offsets.sorted()
			}
			func isModeled(_ member: Int) -> Bool {
				let bodyScope = functions[member].bodyScope
				return !unsupportedScopes.contains(where: { isAncestorOrSelf(bodyScope, of: $0) })
					&& !functions[member].parameterNames.contains(where: { $0.hasPrefix("scope") || $0.hasPrefix("__safeDI_") })
					&& !text(functions[member].lineRange).contains("_ = ")
					&& !functions[member].isSendable
			}
			// A class is valid when its members are modeled and read the same labels, each from a declaration with a spelled
			// type, and every class it names or declares is valid. A label read from more than one declaration is passed.
			var valid = Set(membersByClass.keys.filter { key in
				let members = membersByClass[key, default: []]
				guard members.allSatisfy(isModeled) else { return false }
				var labels: Set<String>?
				for member in members {
					let reads = valueReads(of: member)
					if let labels, labels != Set(reads.map(\.name)) { return false }
					labels = Set(reads.map(\.name))
					if reads.contains(where: { $0.declaration != nilRead && declarations[$0.declaration].typeText == nil }) { return false }
					// One declaration, or `nil`, per label within a member.
					var declarationByLabel = [String: Int]()
					for read in reads {
						if let known = declarationByLabel[read.name], known != read.declaration { return false }
						declarationByLabel[read.name] = read.declaration
					}
				}
				return true
			})
			func requiredClasses(of key: Int) -> Set<Int> {
				var result = Set<Int>()
				for member in membersByClass[key, default: []] {
					for reference in ownReferencesByFunction[member, default: []] {
						if let target = targetFunction(of: reference), let targetClass = classOf[target] { result.insert(targetClass) }
					}
					for nested in nestedByFunction[member, default: []] {
						if let nestedClass = classOf[nested] { result.insert(nestedClass) }
					}
				}
				result.remove(key)
				return result
			}
			var changed = true
			while changed {
				changed = false
				for key in valid.sorted() where !requiredClasses(of: key).isSubset(of: valid) {
					valid.remove(key)
					changed = true
				}
			}
			// The component: every valid class of two or more members, and every class those name or declare.
			var kept = Set(valid.filter { membersByClass[$0, default: []].count > 1 })
			guard !kept.isEmpty else { return fail("no valid class") }
			var worklist = Array(kept)
			while let key = worklist.popLast() {
				for required in requiredClasses(of: key) where !kept.contains(required) {
					kept.insert(required)
					worklist.append(required)
				}
			}
			let keptClasses = kept.sorted { (membersByClass[$0]?.first ?? 0) < (membersByClass[$1]?.first ?? 0) }
			let members = keptClasses.flatMap { membersByClass[$0, default: []] }
			let memberSet = Set(members)
			let memberDeclarations = Set(members.map { functions[$0].declaration })
			// Names: the members' own where they share one no other kept class has, else made unique.
			var nameByClass = [Int: String]()
			var usedNames = Set<String>()
			// Every member is deleted, so a name only members declare is free again.
			let memberRanges = members.map { functions[$0].lineRange }
			var namesDeclaredOnlyInsideMembers = Set(declarations.filter { declaration in memberRanges.contains { $0.contains(declaration.offset) } }.map(\.name))
			for declaration in declarations where !memberRanges.contains(where: { $0.contains(declaration.offset) }) {
				namesDeclaredOnlyInsideMembers.remove(declaration.name)
			}
			let takenNames = allIdentifiers.subtracting(namesDeclaredOnlyInsideMembers)
			for key in keptClasses {
				let classMembers = membersByClass[key, default: []]
				var name = functions[classMembers[0]].name
				while name.hasSuffix("_") {
					name.removeLast()
				}
				while takenNames.contains(name) || usedNames.contains(name) {
					name += "_"
				}
				usedNames.insert(name)
				allIdentifiers.insert(name)
				nameByClass[key] = name
			}
			// Sites: references to members from outside every member.
			let sites = references.filter { reference in
				guard let declaration = reference.declaration, memberDeclarations.contains(declaration) else { return false }
				return !members.contains { functions[$0].lineRange.contains(reference.offset) }
			}
			guard !sites.isEmpty else { return fail("no call from outside") }
			let siteChains = sites.map { chain(of: $0.scope) }
			var placement = siteChains[0]
			for siteChain in siteChains.dropFirst() {
				placement = Array(zip(placement, siteChain).prefix(while: { $0 == $1 }).map(\.0))
			}
			guard var placementScope = placement.last else { return fail("no common scope") }
			while scopes[placementScope].function == nil, let parent = scopes[placementScope].parent {
				placementScope = parent
			}
			for member in members where isAncestorOrSelf(functions[member].bodyScope, of: placementScope) {
				return fail("placement inside a member")
			}
			for site in sites {
				guard let declaration = site.declaration, let function = declarations[declaration].function, let key = classOf[function], let name = nameByClass[key] else {
					return fail("a site names no member")
				}
				// Nothing else of the name between the site and the placement.
				for scope in chain(of: site.scope).drop(while: { $0 != placementScope }) {
					if let other = scopes[scope].names[name], !memberDeclarations.contains(other) {
						return fail("a site would resolve to another declaration")
					}
				}
				if let callee = site.argumentOfCallee, PerTypeEmission.isSendableWrapper(callee) {
					return fail("@Sendable")
				}
				if chain(of: site.scope).drop(while: { $0 != placementScope }).dropFirst().contains(where: { scopes[$0].isSendableBoundary }) {
					return fail("@Sendable")
				}
			}
			guard let lineStarts = statementLineStartsByScope[placementScope], let ranges = statementRangesByScope[placementScope] else {
				return fail("placement has no statements")
			}
			let firstSiteOffset = sites.map(\.offset).min() ?? 0
			guard var anchor = ranges.firstIndex(where: { $0.contains(firstSiteOffset) || $0.lowerBound > firstSiteOffset }) else {
				return fail("no anchor")
			}
			while anchor < lineStarts.count, members.contains(where: { functions[$0].lineRange.lowerBound == lineStarts[anchor] }) {
				anchor += 1
			}
			guard anchor < lineStarts.count else { return fail("no anchor") }
			let anchorLineStart = lineStarts[anchor]
			// A label is captured when every member reads one declaration visible at the placement and declared before the
			// functions; otherwise each class passes it, in the order its first member first reads it.
			func isCapturable(_ declarationIndex: Int, label: String) -> Bool {
				guard declarationIndex != nilRead else { return true }
				let declaration = declarations[declarationIndex]
				return isAncestorOrSelf(declaration.scope, of: placementScope) && declaration.offset < anchorLineStart
					&& !chain(of: placementScope).drop(while: { $0 != declaration.scope }).dropFirst().contains(where: { scopes[$0].names[label] != nil })
			}
			// A call of a member that takes labels reads them where it is made, so the calling member reads them too:
			// each label from the declaration the called member read, unless the caller declares it itself. Passed labels
			// grow until no class takes another.
			var parametersByClass = [Int: [(name: String, type: String)]]()
			var readsByFunction = [Int: [(name: String, declaration: Int)]]()
			func reads(of function: Int) -> [(name: String, declaration: Int)] {
				readsByFunction[function] ?? valueReads(of: function)
			}
			// Every reference to a member that passes labels resolves each where the member it names read it.
			func readDeclaration(of function: Int, label: String) -> Int? {
				reads(of: function).first(where: { $0.name == label })?.declaration
			}
			var passes = 0
			while true {
				passes += 1
				guard passes <= 64 else { return fail("passed labels do not settle") }
				var nextReads = [Int: [(name: String, declaration: Int)]]()
				for member in members {
					let range = functions[member].lineRange
					var ordered = zip(valueReadOffsets(of: member), valueReads(of: member)).map { (offset: $0, name: $1.name, declaration: $1.declaration) }
					for reference in ownReferencesByFunction[member, default: []] {
						guard let target = targetFunction(of: reference), memberSet.contains(target), let targetClass = classOf[target] else { continue }
						for parameter in parametersByClass[targetClass, default: []] {
							guard let declaration = readDeclaration(of: target, label: parameter.name), declaration != nilRead,
							      !range.contains(declarations[declaration].offset)
							else { continue }
							ordered.append((reference.offset, parameter.name, declaration))
						}
					}
					nextReads[member] = ordered.sorted { $0.offset < $1.offset }.map { ($0.name, $0.declaration) }
				}
				readsByFunction = nextReads
				var nextParameters = [Int: [(name: String, type: String)]]()
				for key in keptClasses {
					let readsByMember = membersByClass[key, default: []].map(reads)
					guard Set(readsByMember.map { Set($0.map(\.name)) }).count == 1 else { return fail("members read different labels through calls") }
					var labels = [String]()
					for read in readsByMember[0] where !labels.contains(read.name) {
						labels.append(read.name)
					}
					var parameters = [(name: String, type: String)]()
					for label in labels {
						for memberReads in readsByMember where Set(memberReads.filter { $0.name == label }.map(\.declaration)).count > 1 {
							return fail("a member reads a label from two declarations")
						}
						let resolved = readsByMember.compactMap { memberReads in memberReads.first(where: { $0.name == label })?.declaration }
						if Set(resolved).count == 1, isCapturable(resolved[0], label: label) { continue }
						if resolved.contains(where: { $0 != nilRead && declarations[$0].typeText == nil }) { return fail("a passed label has no spelled type") }
						let types = Set(resolved.filter { $0 != nilRead }.compactMap { declarations[$0].typeText })
						let unwrapped = Set(types.map { $0.hasSuffix("?") ? String($0.dropLast()) : $0 })
						guard unwrapped.count == 1, let base = unwrapped.first else { return fail("a passed label has different types") }
						var type = types.count == 1 && !resolved.contains(nilRead) ? base + (types.first?.hasSuffix("?") == true ? "?" : "") : base + "?"
						if type.contains("->"), !type.hasSuffix("?"), !type.contains("@escaping") { type = "@escaping " + type }
						parameters.append((label, type))
					}
					nextParameters[key] = parameters
				}
				let settled = keptClasses.allSatisfy { key in
					nextParameters[key, default: []].map { "\($0.name):\($0.type)" } == parametersByClass[key, default: []].map { "\($0.name):\($0.type)" }
				}
				parametersByClass = nextParameters
				if settled { break }
			}
			// Every member of a class passes `nil` exactly where its first member does.
			for key in keptClasses {
				let signatures = membersByClass[key, default: []].map { member in
					ownReferencesByFunction[member, default: []].compactMap { reference -> String? in
						guard let target = targetFunction(of: reference), let targetClass = classOf[target] else { return nil }
						let nils = parametersByClass[targetClass, default: []].map { readDeclaration(of: target, label: $0.name) == nilRead ? "nil" : "value" }
						return "\(targetClass):" + nils.joined(separator: ",")
					}
				}
				guard Set(signatures).count == 1 else { return fail("members pass nil at different calls") }
			}
			let referencesToMembers = members.flatMap { ownReferencesByFunction[$0, default: []] }.filter { targetFunction(of: $0).map(memberSet.contains) == true } + sites
			for reference in referencesToMembers {
				guard let target = targetFunction(of: reference), let key = classOf[target] else { continue }
				for parameter in parametersByClass[key, default: []] {
					let read = readDeclaration(of: target, label: parameter.name)
					guard read == nilRead || resolve(parameter.name, from: reference.scope) == read else {
						return fail("a passed label resolves elsewhere at a call")
					}
				}
				if !parametersByClass[key, default: []].isEmpty, reference.callRightParen == nil, reference.argumentOfCallee == nil {
					return fail("a member that takes labels is referred to other than by a call or a wrapper")
				}
			}
			var indentationEnd = anchorLineStart
			while indentationEnd < source.count, source[indentationEnd] == UInt8(ascii: " ") {
				indentationEnd += 1
			}
			let anchorIndentation = text(anchorLineStart..<indentationEnd)
			func renames(in references: [Reference]) -> [Edit] {
				references.flatMap { reference -> [Edit] in
					guard let target = targetFunction(of: reference), memberSet.contains(target), let key = classOf[target], let name = nameByClass[key] else { return [] }
					let parameters = parametersByClass[key, default: []]
					let nameRange = reference.offset..<(reference.offset + reference.length)
					let arguments = parameters.map { "\($0.name): \(readDeclaration(of: target, label: $0.name) == nilRead ? "nil" : $0.name)" }.joined(separator: ", ")
					if parameters.isEmpty {
						return name == reference.name ? [] : [.replace(nameRange, name)]
					}
					if let rightParen = reference.callRightParen {
						return (name == reference.name ? [] : [.replace(nameRange, name)]) + [.insert(rightParen, order: 0, (reference.callHasArguments ? ", " : "") + arguments)]
					}
					return [.replace(nameRange, "{ \(name)(\(arguments)) }")]
				}
			}
			// Each class's function: its first member's own text, renamed.
			var inserted = ""
			for key in keptClasses {
				guard let representative = membersByClass[key]?.first, let name = nameByClass[key] else { continue }
				let function = functions[representative]
				var edits = nestedByFunction[representative, default: []].map { Edit.replace(functions[$0].lineRange, "") }
				edits += renames(in: ownReferencesByFunction[representative, default: []])
				let parameterNames = Set(parametersByClass[key, default: []].map(\.name))
				for argument in ownNilArgumentsByFunction[representative, default: []] where parameterNames.contains(argument.label) {
					edits.append(.replace(argument.offset..<(argument.offset + 3), argument.label))
				}
				let parameters = parametersByClass[key, default: []]
				let ownParameters = unifiedParametersText(of: membersByClass[key, default: []])
				if !parameters.isEmpty || ownParameters != function.parametersText {
					let parameterList = ([ownParameters].filter { !$0.isEmpty } + parameters.map { "\($0.name): \($0.type)" }).joined(separator: ", ")
					edits.append(.replace(function.headerRange, "func \(name)(\(parameterList))\(function.returnType.isEmpty ? "" : " -> \(function.returnType)") "))
				} else if name != function.name {
					edits.append(.replace(function.nameRange, name))
				}
				let rendered = render(function.lineRange, edits: edits)
				inserted += rendered.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
					guard !line.isEmpty else { return String(line) }
					return anchorIndentation + (line.hasPrefix(function.indentation) ? String(line.dropFirst(function.indentation.count)) : String(line))
				}.joined(separator: "\n")
			}
			var edits = members.map { Edit.replace(functions[$0].lineRange, "") }
			edits += renames(in: sites)
			edits.append(.insert(anchorLineStart, order: 0, inserted))
			statistics.cyclicComponents += 1
			statistics.cyclicGroups += keptClasses.count
			statistics.cyclicPlaces += members.count
			return render(bodyStart..<bodyEnd, edits: edits)
		}

		// MARK: Writing

		private enum Edit {
			case replace(Range<Int>, String)
			case insert(Int, order: Int, String)

			var start: Int {
				switch self {
				case let .replace(range, _): range.lowerBound
				case let .insert(offset, _, _): offset
				}
			}
		}

		private func apply(_ plans: [Plan]) -> String {
			var edits = [Edit]()
			let orderedPlans = plans.sorted { $0.firstSiteOffset < $1.firstSiteOffset }
			for (order, plan) in orderedPlans.enumerated() {
				let representative = functions[plan.members[0]]
				let representativeDeclaration = representative.declaration
				// Rewrite every call and wrapper argument.
				let argumentsText = plan.parameters.map { "\($0.name): \($0.name)" }.joined(separator: ", ")
				var representativeEdits = [Edit]()
				for reference in references {
					guard let declaration = reference.declaration,
					      plan.members.contains(where: { functions[$0].declaration == declaration })
					else { continue }
					let insideMember = plan.members.firstIndex(where: { functions[$0].lineRange.contains(reference.offset) })
					// References inside a member other than the representative go with it.
					if let insideMember, insideMember != 0 { continue }
					var referenceEdits = [Edit]()
					let nameRange = reference.offset..<(reference.offset + reference.length)
					if let rightParen = reference.callRightParen {
						if plan.newName != reference.name {
							referenceEdits.append(.replace(nameRange, plan.newName))
						}
						if !plan.parameters.isEmpty {
							referenceEdits.append(.insert(rightParen, order: 0, (reference.callHasArguments ? ", " : "") + argumentsText))
						}
					} else if plan.parameters.isEmpty {
						if plan.newName != reference.name {
							referenceEdits.append(.replace(nameRange, plan.newName))
						}
					} else {
						referenceEdits.append(.replace(nameRange, "{ \(plan.newName)(\(argumentsText)) }"))
					}
					if insideMember == 0 {
						representativeEdits += referenceEdits
					} else {
						edits += referenceEdits
					}
				}
				_ = representativeDeclaration
				// The header.
				let parameterList = ([unifiedParametersText(of: plan.members)].filter { !$0.isEmpty } + plan.parameters.map { "\($0.name): \($0.type)" }).joined(separator: ", ")
				let header = "\(plan.isSendable ? "@Sendable " : "")func \(plan.newName)(\(parameterList))\(representative.returnType.isEmpty ? "" : " -> \(representative.returnType)") "
				representativeEdits.append(.replace(representative.headerRange, header))
				let rendered = render(representative.lineRange, edits: representativeEdits)
				let reindented = rendered.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
					guard !line.isEmpty else { return String(line) }
					return plan.anchorIndentation + (line.hasPrefix(representative.indentation) ? String(line.dropFirst(representative.indentation.count)) : String(line))
				}.joined(separator: "\n")
				// Delete every member, and place the shared function.
				for member in plan.members {
					edits.append(.replace(functions[member].lineRange, ""))
				}
				edits.append(.insert(plan.anchorLineStart, order: order, reindented))
			}
			let body = render(bodyStart..<bodyEnd, edits: edits)
			return body
		}

		private func render(_ range: Range<Int>, edits: [Edit]) -> String {
			let sorted = edits.enumerated().sorted { lhs, rhs in
				if lhs.element.start != rhs.element.start { return lhs.element.start < rhs.element.start }
				// Insertions come before a replacement that starts at the same offset.
				switch (lhs.element, rhs.element) {
				case let (.insert(_, lhsOrder, _), .insert(_, rhsOrder, _)): return lhsOrder == rhsOrder ? lhs.offset < rhs.offset : lhsOrder < rhsOrder
				case (.insert, .replace): return true
				case (.replace, .insert): return false
				case (.replace, .replace): return lhs.offset < rhs.offset
				}
			}.map(\.element)
			var output = [UInt8]()
			var index = range.lowerBound
			for edit in sorted {
				switch edit {
				case let .replace(editRange, replacement):
					guard editRange.lowerBound >= index, editRange.upperBound <= range.upperBound else { continue }
					output += source[index..<editRange.lowerBound]
					output += Array(replacement.utf8)
					index = editRange.upperBound
				case let .insert(offset, _, insertion):
					guard offset >= index, offset <= range.upperBound else { continue }
					output += source[index..<offset]
					output += Array(insertion.utf8)
					index = offset
				}
			}
			output += source[index..<range.upperBound]
			return String(decoding: output, as: UTF8.self)
		}
	}

	static func isSendableWrapper(_ callee: String) -> Bool {
		callee.hasPrefix("Sendable") || callee.hasPrefix("SafeDI.Sendable")
	}

	/// The type a binding's initializer spells: the called type of a construction.
	static func inferredType(of expression: ExprSyntax) -> String? {
		guard let call = expression.as(FunctionCallExprSyntax.self) else { return nil }
		let callee = call.calledExpression
		if callee.is(DeclReferenceExprSyntax.self) || callee.is(GenericSpecializationExprSyntax.self) {
			let name = callee.trimmedDescription
			// A builder function's call has no spelled type.
			return name.hasPrefix("__safeDI_") ? nil : name
		}
		if let member = callee.as(MemberAccessExprSyntax.self), let base = member.base,
		   member.declName.baseName.text == "instantiate"
		{
			return base.trimmedDescription
		}
		return nil
	}
}
