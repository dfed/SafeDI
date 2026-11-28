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

import SafeDICore
import SwiftParser
import SwiftSyntax
import Testing

extension HoleSiteRecordObservation {
	/// An observer that records an issue for each way the site's record disagrees with its text, then hands the site to
	/// `enclosingObserver`.
	static func checkingRecords(handingOn enclosingObserver: (@Sendable (HoleSiteRecordObservation) -> Void)?) -> @Sendable (HoleSiteRecordObservation) -> Void {
		{ site in
			for mismatch in site.recordMismatches {
				Issue.record(Comment(rawValue: mismatch))
			}
			enclosingObserver?(site)
		}
	}

	/// Each way the record disagrees with the text: a name the text reads that the record lists neither as a read nor as a
	/// binding, a read the text does not make, and a binding the text does not declare. A name the text reads that starts
	/// with a capital letter, or that it calls directly, is a type, which no record lists.
	var recordMismatches: [String] {
		Self.recordMismatches(text: text, readNames: readNames, boundNames: boundNames, place: "a hole’s site")
	}

	/// Each way the record of `place`, written as `text`, disagrees with it, as `recordMismatches` says of a hole's site.
	/// Each function named in `keptFunctionNames` (a seam call's fills and dispatchers kept in place) is a declaration of
	/// the text, and binds its own parameters and values: of its body, only what it reads of the code around it is a read of
	/// the text.
	static func recordMismatches(text: String, readNames: [String]?, boundNames: [String], keptFunctionNames: [String] = [], place: String) -> [String] {
		let syntax = Parser.parse(source: text)
		let visitor = NameVisitor(keptFunctionNames: Set(keptFunctionNames.map(Self.withoutBackticks)))
		visitor.walk(syntax)
		let bound = Set(boundNames.map(Self.withoutBackticks))
		var mismatches = [String]()
		for name in Self.withoutBackticks(visitor.declaredNames).symmetricDifference(bound).sorted() {
			mismatches.append("The record of \(place) lists `\(name)` as bound where its text \(bound.contains(name) ? "does not declare it" : "declares it unlisted"):\n\(text)")
		}
		guard let readNames else { return mismatches }
		let reads = Set(readNames.map(Self.withoutBackticks))
		let referenced = Self.withoutBackticks(visitor.referencedNames)
		for name in reads.subtracting(referenced).sorted() {
			mismatches.append("The record of \(place) lists a read of `\(name)` its text does not make:\n\(text)")
		}
		let typeNames = Self.withoutBackticks(visitor.calledNames)
		for name in referenced.subtracting(reads).subtracting(bound).subtracting(typeNames).sorted() where name.first?.isUppercase == false {
			mismatches.append("The text of \(place) reads `\(name)`, which its record does not list:\n\(text)")
		}
		return mismatches
	}

	private static func withoutBackticks(_ name: String) -> String {
		name.filter { $0 != "`" }
	}

	private static func withoutBackticks(_ names: Set<String>) -> Set<String> {
		Set(names.map(withoutBackticks))
	}

	/// The names a site's text declares, refers to as values, and calls directly.
	private final class NameVisitor: SyntaxVisitor {
		var declaredNames = Set<String>()
		var referencedNames = Set<String>()
		var calledNames = Set<String>()
		/// The functions whose bodies bind their own names (`recordMismatches(text:readNames:boundNames:keptFunctionNames:place:)`).
		private let keptFunctionNames: Set<String>

		init(keptFunctionNames: Set<String>) {
			self.keptFunctionNames = keptFunctionNames
			super.init(viewMode: .sourceAccurate)
		}

		override func visit(_ node: IdentifierPatternSyntax) -> SyntaxVisitorContinueKind {
			declaredNames.insert(node.identifier.text)
			return .visitChildren
		}

		/// An attribute, such as the `@inline(never)` a seam’s tree declares its local functions with, reads no value.
		override func visit(_: AttributeSyntax) -> SyntaxVisitorContinueKind {
			.skipChildren
		}

		override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
			declaredNames.insert(node.name.text)
			guard keptFunctionNames.contains(node.name.text) else { return .visitChildren }
			let freeNames = FreeNameVisitor()
			freeNames.walk(node)
			referencedNames.formUnion(freeNames.referencedNames)
			calledNames.formUnion(freeNames.calledNames)
			return .skipChildren
		}

		override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
			if let memberAccess = node.parent?.as(MemberAccessExprSyntax.self), memberAccess.declName.id == node.id {
				return .visitChildren
			}
			referencedNames.insert(node.baseName.text)
			return .visitChildren
		}

		override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
			var callee = node.calledExpression
			if let specialization = callee.as(GenericSpecializationExprSyntax.self) {
				callee = specialization.expression
			}
			if let reference = callee.as(DeclReferenceExprSyntax.self) {
				calledNames.insert(reference.baseName.text)
			}
			return .visitChildren
		}
	}
	/// The names a function's text reads of the code around it: each name it refers to that neither it nor a function or
	/// closure inside it declares, as a parameter or a value, around the reference. A name declared anywhere in a function or
	/// closure is taken as declared throughout it, as Swift lets a local function be called before its declaration.
	private final class FreeNameVisitor: SyntaxVisitor {
		var referencedNames = Set<String>()
		var calledNames = Set<String>()

		/// A function or closure being walked: what it declares, and the names it refers to that are not yet resolved.
		private struct Scope {
			var declaredNames = Set<String>()
			var references = [(name: String, isCall: Bool)]()
		}

		private var scopes = [Scope]()

		init() {
			super.init(viewMode: .sourceAccurate)
		}

		override func visit(_: AttributeSyntax) -> SyntaxVisitorContinueKind {
			.skipChildren
		}

		override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
			// The function walked first is declared by the text around it.
			if !scopes.isEmpty {
				declare(node.name.text)
			}
			scopes.append(Scope())
			return .visitChildren
		}

		override func visitPost(_: FunctionDeclSyntax) {
			closeScope()
		}

		override func visit(_: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
			scopes.append(Scope())
			return .visitChildren
		}

		override func visitPost(_: ClosureExprSyntax) {
			closeScope()
		}

		override func visit(_ node: FunctionParameterSyntax) -> SyntaxVisitorContinueKind {
			declare((node.secondName ?? node.firstName).text)
			return .visitChildren
		}

		override func visit(_ node: ClosureParameterSyntax) -> SyntaxVisitorContinueKind {
			declare((node.secondName ?? node.firstName).text)
			return .visitChildren
		}

		override func visit(_ node: ClosureShorthandParameterSyntax) -> SyntaxVisitorContinueKind {
			declare(node.name.text)
			return .visitChildren
		}

		override func visit(_ node: IdentifierPatternSyntax) -> SyntaxVisitorContinueKind {
			declare(node.identifier.text)
			return .visitChildren
		}

		override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
			if let memberAccess = node.parent?.as(MemberAccessExprSyntax.self), memberAccess.declName.id == node.id {
				return .visitChildren
			}
			// An anonymous closure parameter, such as `$0`, is its closure's own.
			guard !node.baseName.text.hasPrefix("$") else { return .visitChildren }
			var callee = Syntax(node)
			if let specialization = callee.parent?.as(GenericSpecializationExprSyntax.self) {
				callee = Syntax(specialization)
			}
			let isCall = callee.parent?.as(FunctionCallExprSyntax.self)?.calledExpression.id == callee.id
			scopes[scopes.count - 1].references.append((node.baseName.text, isCall))
			return .visitChildren
		}

		private func declare(_ name: String) {
			scopes[scopes.count - 1].declaredNames.insert(name)
		}

		/// Ends the innermost scope: each of its references it does not declare is left to the scope around it, or read of
		/// the code around the function where none is.
		private func closeScope() {
			let scope = scopes.removeLast()
			for reference in scope.references where !scope.declaredNames.contains(reference.name) {
				if scopes.isEmpty {
					referencedNames.insert(reference.name)
					if reference.isCall {
						calledNames.insert(reference.name)
					}
				} else {
					scopes[scopes.count - 1].references.append(reference)
				}
			}
		}
	}
}
